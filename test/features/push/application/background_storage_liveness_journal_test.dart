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
          phaseName: BackgroundStorageDeadlinePhaseName.displayEligibility,
          outcome: BackgroundStorageTerminalOutcome.storageDeferred,
          elapsed: const Duration(milliseconds: 2300),
          phaseElapsed: const Duration(milliseconds: 2001),
          budget: const Duration(seconds: 2),
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
        'phaseName',
        'outcome',
        'elapsedBucket',
        'elapsedMs',
        'phaseElapsedMs',
        'budgetMs',
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
          'phaseName': 'display_eligibility',
          'outcome': 'storage_deferred',
          'elapsedBucket': '2s_to_8s',
          'elapsedMs': '2300',
          'phaseElapsedMs': '2001',
          'budgetMs': '2000',
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
            phaseName: BackgroundStorageDeadlinePhaseName.previewResolution,
            outcome: BackgroundStorageTerminalOutcome.notificationSuppressed,
            elapsed: const Duration(milliseconds: 10),
            phaseElapsed: const Duration(milliseconds: 10),
            budget: const Duration(seconds: 2),
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
          phaseName: BackgroundStorageDeadlinePhaseName.durableEffectAuthority,
          outcome: BackgroundStorageTerminalOutcome.storageDeferred,
          elapsed: Duration.zero,
          phaseElapsed: Duration.zero,
          budget: const Duration(seconds: 2),
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
          phaseName: BackgroundStorageDeadlinePhaseName.previewResolution,
          outcome: BackgroundStorageTerminalOutcome.storageDeferred,
          elapsed: Duration.zero,
          phaseElapsed: Duration.zero,
          budget: const Duration(seconds: 2),
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
        phaseName: BackgroundStorageDeadlinePhaseName.durableEffectAuthority,
        outcome: BackgroundStorageTerminalOutcome.storageDeferred,
        elapsed: Duration.zero,
        phaseElapsed: Duration.zero,
        budget: const Duration(seconds: 2),
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
      phaseName: BackgroundStorageDeadlinePhaseName.recentBackgroundRead,
      outcome: BackgroundStorageTerminalOutcome.notificationSuppressed,
      elapsed: Duration.zero,
      phaseElapsed: Duration.zero,
      budget: const Duration(seconds: 2),
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
        phaseName: BackgroundStorageDeadlinePhaseName.unknown,
        outcome: BackgroundStorageTerminalOutcome.storageDeferred,
        elapsed: const Duration(seconds: 8),
        phaseElapsed: const Duration(seconds: 8),
        budget: const Duration(seconds: 2),
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
          phaseName: BackgroundStorageDeadlinePhaseName.previewResolution,
          outcome: BackgroundStorageTerminalOutcome.storageDeferred,
          elapsed: Duration.zero,
          phaseElapsed: Duration.zero,
          budget: const Duration(seconds: 2),
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
        phaseName: BackgroundStorageDeadlinePhaseName.recentRemoteMark,
        outcome: BackgroundStorageTerminalOutcome.notificationSuppressed,
        elapsed: const Duration(milliseconds: 100),
        phaseElapsed: const Duration(milliseconds: 100),
        budget: const Duration(seconds: 2),
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
          phaseName: BackgroundStorageDeadlinePhaseName.displayEligibility,
          outcome: BackgroundStorageTerminalOutcome.notificationSuppressed,
          elapsed: Duration.zero,
          phaseElapsed: Duration.zero,
          budget: const Duration(seconds: 2),
        ),
        completes,
      );
    },
  );

  // ---------------------------------------------------------------------
  // Plan 388 (G21/G22) — exact timings on the durable surface, and a raw
  // phase identifier that stays inside a closed domain.
  // ---------------------------------------------------------------------

  test('terminal records carry exact timings across the atomic publish', () async {
    final journal = BackgroundStorageLivenessJournal(
      directoryResolver: () async => root,
      randomNonce: () => 3,
      buildMode: BackgroundStorageBuildMode.release,
    );

    // The three durations mirror the real device sample recomputed for plan
    // 388: a 2.170 s total that overran a 2.000 s phase budget by ~170 ms.
    // Nothing in the six-key record could tell that from an 8 s stall.
    await journal.recordTerminal(
      kind: BackgroundStorageMessageKind.groupReaction,
      phase: BackgroundStorageLivenessPhase.displayEligibility,
      phaseName: BackgroundStorageDeadlinePhaseName.displayEligibility,
      outcome: BackgroundStorageTerminalOutcome.storageDeferred,
      elapsed: const Duration(milliseconds: 2170),
      phaseElapsed: const Duration(milliseconds: 2001),
      budget: const Duration(seconds: 2),
    );

    final published = root
        .listSync(followLinks: false)
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'))
        .toList(growable: false);
    expect(published, hasLength(1));
    // Read back off disk AFTER the temporary -> atomic rename publish.
    expect(jsonDecode(published.single.readAsStringSync()), <String, dynamic>{
      'kind': 'group_reaction',
      'phase': 'display_eligibility',
      'phaseName': 'display_eligibility',
      'outcome': 'storage_deferred',
      'elapsedBucket': '2s_to_8s',
      'elapsedMs': '2170',
      'phaseElapsedMs': '2001',
      'budgetMs': '2000',
      'buildMode': 'release',
      'engineRole': 'flutterfire_background',
    });
    expect(
      root.listSync().where((entity) => entity.path.endsWith('.tmp')),
      isEmpty,
    );
  });

  test('the raw phase identifier is closed-domain and tells local_state phases apart', () async {
    // 1. Closed domain. The journal's own doc comment states the invariant:
    //    values are fixed rather than caller-provided strings so an identifier
    //    cannot accidentally be persisted. The raw phase name re-opens that
    //    surface, so every `storageDeadline.run(` first argument in the handler
    //    must still be a compile-time literal drawn from the enum.
    final handlerSource = File(
      'lib/features/push/application/background_message_handler.dart',
    ).readAsStringSync();
    final runSiteArguments =
        RegExp(r'storageDeadline\.run(?:<[^>]*>)?\(\s*([^,]+),')
            .allMatches(handlerSource)
            .map((match) => match.group(1)!.trim())
            .toList(growable: false);
    expect(
      runSiteArguments.length,
      greaterThanOrEqualTo(11),
      reason:
          'the census must still find every deadline-guarded phase; a smaller '
          'count means the regex stopped matching, not that phases vanished',
    );
    final domain = BackgroundStorageDeadlinePhaseName.values
        .map((value) => value.wireName)
        .toSet();
    for (final argument in runSiteArguments) {
      expect(
        RegExp(r"^'[a-z0-9_]+'$").hasMatch(argument),
        isTrue,
        reason: 'phase names must stay compile-time literals, found: $argument',
      );
      expect(
        domain,
        contains(argument.substring(1, argument.length - 1)),
        reason: 'every run-site phase name must be a declared domain member',
      );
    }

    // 2. EVERY member round-trips, and an out-of-domain value degrades
    //    instead of throwing or leaking. Asserting only the handful of phases
    //    the behavioural tests exercise would let a three-case mapping — or a
    //    transposition of two never-driven members — pass.
    for (final member in BackgroundStorageDeadlinePhaseName.values) {
      expect(
        BackgroundStorageDeadlinePhaseName.fromWireName(member.wireName),
        member,
        reason: '${member.wireName} must map back to itself',
      );
    }
    expect(
      BackgroundStorageDeadlinePhaseName.values
          .map((member) => member.wireName)
          .toSet(),
      hasLength(BackgroundStorageDeadlinePhaseName.values.length),
      reason: 'two members sharing a wire name would make the map ambiguous',
    );
    // The domain, frozen member-by-member. Round-tripping alone cannot see a
    // transposition — swap two members' wire names and every `fromWireName`
    // assertion still holds — but a caller that names a member explicitly
    // (as the fixtures above do) would then persist the wrong phase.
    expect(<String, String>{
      for (final member in BackgroundStorageDeadlinePhaseName.values)
        member.name: member.wireName,
    }, <String, String>{
      'directPostShowValidation': 'direct_post_show_validation',
      'directStage': 'direct_stage',
      'displayEligibility': 'display_eligibility',
      'durableEffectAuthority': 'durable_effect_authority',
      'groupPostShowValidation': 'group_post_show_validation',
      'pendingOverlay': 'pending_overlay',
      'previewResolution': 'preview_resolution',
      'recentBackgroundMark': 'recent_background_mark',
      'recentBackgroundRead': 'recent_background_read',
      'recentRemoteMark': 'recent_remote_mark',
      'resolvedStage': 'resolved_stage',
      'unknown': 'unknown',
    });
    expect(
      BackgroundStorageDeadlinePhaseName.fromWireName('peer-abc123'),
      BackgroundStorageDeadlinePhaseName.unknown,
    );
    // Every run-site literal censused above must also resolve to a member that
    // is not the fallback — the domain check alone is satisfied by a mapping
    // that degrades a real phase to `unknown`.
    for (final argument in runSiteArguments) {
      final wireName = argument.substring(1, argument.length - 1);
      expect(
        BackgroundStorageDeadlinePhaseName.fromWireName(wireName).wireName,
        wireName,
        reason: '$wireName must resolve to its own member, not the fallback',
      );
    }

    // 3. Discrimination on the persisted record. `preview_resolution` and
    //    `durable_effect_authority` are the only two phases the liveness enum
    //    does not name, so both still map to `local_state`.
    final journal = BackgroundStorageLivenessJournal(
      directoryResolver: () async => root,
      randomNonce: () => 0,
      buildMode: BackgroundStorageBuildMode.release,
    );
    for (final phaseName in <BackgroundStorageDeadlinePhaseName>[
      BackgroundStorageDeadlinePhaseName.previewResolution,
      BackgroundStorageDeadlinePhaseName.durableEffectAuthority,
    ]) {
      await journal.recordTerminal(
        kind: BackgroundStorageMessageKind.directMessage,
        phase: BackgroundStorageLivenessPhase.localState,
        phaseName: phaseName,
        outcome: BackgroundStorageTerminalOutcome.storageDeferred,
        elapsed: const Duration(milliseconds: 2170),
        phaseElapsed: const Duration(milliseconds: 2001),
        budget: const Duration(seconds: 2),
      );
    }
    final decoded = root
        .listSync(followLinks: false)
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'))
        .map((file) => jsonDecode(file.readAsStringSync()))
        .cast<Map<String, dynamic>>()
        .toList(growable: false);
    expect(decoded, hasLength(2));
    for (final record in decoded) {
      // Both facts bound on ONE record: the mapped enum still collapses and
      // the raw identifier still discriminates.
      expect(record['phase'], 'local_state');
      expect(record['phaseName'], isNot('local_state'));
    }
    expect(
      decoded.map((record) => record['phaseName']).toSet(),
      <String>{'preview_resolution', 'durable_effect_authority'},
    );
    // 4. The redaction contract still holds over the widened record.
    for (final record in decoded) {
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
  });

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
