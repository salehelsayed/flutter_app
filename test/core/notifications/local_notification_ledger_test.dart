import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/notifications/bounded_posix_flock.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'TC-372-01 v1 codec and state machine accept only legal monotonic transitions',
    () {
      final fixture =
          jsonDecode(
                File(
                  'test/shared/fixtures/local_notification_ledger_v1.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final template = Map<String, Object?>.from(
        fixture['recordTemplate']! as Map,
      );

      final accepted = fixture['acceptedTransitions']! as List<Object?>;
      expect(accepted, hasLength(14));
      for (final rawVector in accepted) {
        final vector = Map<String, Object?>.from(rawVector! as Map);
        final current = _record(_patched(template, vector['before']! as Map));
        final next = _record(_patched(template, vector['after']! as Map));

        final transitioned =
            LocalNotificationLedgerStateMachineV1.tryTransition(
              current: current,
              expectedRevision: vector['expectedRevision']! as int,
              next: next,
            );

        expect(
          transitioned?.toJson(),
          next.toJson(),
          reason: '${vector['name']} must be a legal monotonic CAS',
        );
      }

      final rejected = fixture['rejectedTransitions']! as List<Object?>;
      for (final rawVector in rejected) {
        final vector = Map<String, Object?>.from(rawVector! as Map);
        final current = _record(_patched(template, vector['before']! as Map));
        final next = _record(_patched(template, vector['after']! as Map));
        expect(
          LocalNotificationLedgerStateMachineV1.tryTransition(
            current: current,
            expectedRevision: vector['expectedRevision']! as int,
            next: next,
          ),
          isNull,
          reason: '${vector['name']} must not gain effect authority',
        );
      }

      final encodedEnvelope = jsonEncode(fixture['validEnvelope']);
      final envelope = LocalNotificationLedgerCodecV1.tryDecode(
        encodedEnvelope,
      );
      expect(envelope, isNotNull);
      expect(
        jsonDecode(LocalNotificationLedgerCodecV1.encode(envelope!)),
        fixture['validEnvelope'],
      );

      for (final rawMutation
          in fixture['invalidEnvelopeMutations']! as List<Object?>) {
        final mutation = Map<String, Object?>.from(rawMutation! as Map);
        final invalid = _deepCopy(
          fixture['validEnvelope']! as Map<String, Object?>,
        );
        _writePath(invalid, mutation['path']! as String, mutation['value']);
        expect(
          LocalNotificationLedgerCodecV1.tryDecode(jsonEncode(invalid)),
          isNull,
          reason: '${mutation['name']} must fail closed',
        );
      }
    },
  );

  test(
    'TC-372-02 atomic store binding rebind and bounds preserve current authority and future bytes',
    () async {
      final root = await Directory.systemTemp.createTemp('ledger-372-02-');
      addTearDown(() => root.delete(recursive: true));
      final now = DateTime.utc(2026, 8, 16, 12);
      final bindingA = _binding('c');
      final bindingB = _binding('d');
      final store = LocalNotificationLedgerStore(
        directory: root,
        nowUtc: () => now,
      );

      final initialized = await store.initializeOrRebind(
        currentOpaqueBinding: bindingA,
      );
      expect(initialized?.storeRevision, 1);
      expect(initialized?.records, isEmpty);
      expect(store.ledgerFile.existsSync(), isTrue);
      expect(store.coordinationLockFile.existsSync(), isTrue);

      final reopened = LocalNotificationLedgerStore(
        directory: root,
        nowUtc: () => now,
      );
      expect(
        (await reopened.read(currentOpaqueBinding: bindingA))?.toJson(),
        initialized?.toJson(),
      );

      final beforeFault = await store.ledgerFile.readAsBytes();
      final faulting = LocalNotificationLedgerStore(
        directory: root,
        nowUtc: () => now,
        beforeRename: (prepared, target) async {
          expect(prepared.existsSync(), isTrue);
          expect(target.path, store.ledgerFile.path);
          throw FileSystemException('injected rename boundary');
        },
      );
      expect(
        await faulting.mutate(
          currentOpaqueBinding: bindingA,
          mutation: (current) => current.copyWith(
            storeRevision: current.storeRevision + 1,
            claimsSuspended: true,
          ),
        ),
        isNull,
      );
      expect(await store.ledgerFile.readAsBytes(), beforeFault);
      expect(
        root.listSync().whereType<File>().where(
          (file) => file.path.endsWith('.tmp'),
        ),
        isEmpty,
      );

      var reachedDirectorySyncBoundary = false;
      final syncFaulting = LocalNotificationLedgerStore(
        directory: root,
        nowUtc: () => now,
        afterRenameBeforeDirectorySync: (target) async {
          reachedDirectorySyncBoundary = true;
          expect(target.path, store.ledgerFile.path);
          throw FileSystemException('injected directory fsync boundary');
        },
      );
      expect(
        await syncFaulting.mutate(
          currentOpaqueBinding: bindingA,
          mutation: (current) => current.copyWith(
            storeRevision: current.storeRevision + 1,
            claimsSuspended: true,
          ),
        ),
        isNull,
        reason: 'post-rename fsync uncertainty cannot grant new authority',
      );
      expect(reachedDirectorySyncBoundary, isTrue);
      final wholePostRename = await store.read(currentOpaqueBinding: bindingA);
      expect(wholePostRename?.storeRevision, 2);
      expect(wholePostRename?.claimsSuspended, isTrue);
      expect(
        LocalNotificationLedgerCodecV1.tryDecode(
          await store.ledgerFile.readAsString(),
        ),
        isNotNull,
        reason: 'reopen sees one whole authoritative version, never torn JSON',
      );

      final suspended = await store.suspendClaims(
        currentOpaqueBinding: bindingA,
      );
      expect(suspended?.claimsSuspended, isTrue);
      expect(suspended?.storeRevision, 2);
      final resumedSameBinding = await store.initializeOrRebind(
        currentOpaqueBinding: bindingA,
      );
      expect(resumedSameBinding?.claimsSuspended, isFalse);
      expect(resumedSameBinding?.storeRevision, 3);
      expect(
        resumedSameBinding?.records,
        suspended?.records,
        reason: 'post-crash same-binding startup preserves exact authority',
      );
      final resuspended = await store.suspendClaims(
        currentOpaqueBinding: bindingA,
      );
      expect(resuspended?.claimsSuspended, isTrue);
      expect(resuspended?.storeRevision, 4);
      final suspendedBytes = await store.ledgerFile.readAsBytes();
      expect(
        await store.read(currentOpaqueBinding: bindingB),
        isNull,
        reason: 'copied bytes cannot authorize a different binding',
      );
      expect(await store.ledgerFile.readAsBytes(), suspendedBytes);

      final rebound = await store.initializeOrRebind(
        currentOpaqueBinding: bindingB,
      );
      expect(rebound?.opaqueBinding, bindingB);
      expect(rebound?.storeRevision, 1);
      expect(rebound?.claimsSuspended, isFalse);
      expect(rebound?.records, isEmpty);

      await BoundedPosixFlock.withExclusive(
        store.coordinationLockFile,
        () async {
          final lockHeld = await store.readLockHeld(
            currentOpaqueBinding: bindingB,
          );
          expect(lockHeld, isNotNull);
          final changed = await store.mutateLockHeld(
            currentOpaqueBinding: bindingB,
            mutation: (current) => current.copyWith(
              storeRevision: current.storeRevision + 1,
              records: <String, LocalNotificationRecordV1>{
                _digest('1'): _readyRecord(
                  eventCorrelation: _digest('1'),
                  conversationDigest: _digest('a'),
                ),
              },
            ),
          );
          expect(changed?.records, hasLength(1));
        },
      );

      final boundedRoot = await Directory.systemTemp.createTemp(
        'ledger-372-bounds-',
      );
      addTearDown(() => boundedRoot.delete(recursive: true));
      final bounded = LocalNotificationLedgerStore(
        directory: boundedRoot,
        nowUtc: () => now,
        maxRecords: 2,
      );
      await bounded.initializeOrRebind(currentOpaqueBinding: bindingA);
      final pruned = await bounded.mutate(
        currentOpaqueBinding: bindingA,
        mutation: (current) => current.copyWith(
          storeRevision: current.storeRevision + 1,
          records: <String, LocalNotificationRecordV1>{
            _digest('1'): _readyRecord(
              eventCorrelation: _digest('1'),
              conversationDigest: _digest('a'),
            ),
            _digest('2'): _settledRecord(
              eventCorrelation: _digest('2'),
              conversationDigest: _digest('b'),
              terminalAtUtc: '2026-08-01T10:00:00.000Z',
              settledAtUtc: '2026-08-01T10:00:01.000Z',
            ),
            _digest('3'): _readyRecord(
              eventCorrelation: _digest('3'),
              conversationDigest: _digest('c'),
            ),
          },
        ),
      );
      expect(pruned?.records.keys, {_digest('1'), _digest('3')});

      final beforeCapacityRefusal = await bounded.ledgerFile.readAsBytes();
      expect(
        await bounded.mutate(
          currentOpaqueBinding: bindingA,
          mutation: (current) => current.copyWith(
            storeRevision: current.storeRevision + 1,
            records: <String, LocalNotificationRecordV1>{
              ...current.records,
              _digest('4'): _readyRecord(
                eventCorrelation: _digest('4'),
                conversationDigest: _digest('d'),
              ),
            },
          ),
        ),
        isNull,
        reason: 'unresolved authority cannot be evicted for capacity',
      );
      expect(await bounded.ledgerFile.readAsBytes(), beforeCapacityRefusal);

      final corruptRoot = await Directory.systemTemp.createTemp(
        'ledger-372-corrupt-',
      );
      addTearDown(() => corruptRoot.delete(recursive: true));
      final corrupt = LocalNotificationLedgerStore(directory: corruptRoot);
      const malformed = '{"schemaVersion":1,"records":';
      corruptRoot.createSync(recursive: true);
      corrupt.ledgerFile.writeAsStringSync(malformed, flush: true);
      final repaired = await corrupt.initializeOrRebind(
        currentOpaqueBinding: bindingA,
      );
      expect(repaired?.records, isEmpty);
      final quarantines = corruptRoot
          .listSync()
          .whereType<File>()
          .where((file) => file.path.contains('$fileSeparatorMarker.corrupt-'))
          .toList();
      expect(quarantines, hasLength(1));
      expect(quarantines.single.readAsStringSync(), malformed);

      final futureRoot = await Directory.systemTemp.createTemp(
        'ledger-372-future-',
      );
      addTearDown(() => futureRoot.delete(recursive: true));
      final future = LocalNotificationLedgerStore(directory: futureRoot);
      const futureBytes = '{"schemaVersion":2,"future":"immutable"}';
      futureRoot.createSync(recursive: true);
      future.ledgerFile.writeAsStringSync(futureBytes, flush: true);
      expect(
        await future.initializeOrRebind(currentOpaqueBinding: bindingA),
        isNull,
      );
      expect(future.ledgerFile.readAsStringSync(), futureBytes);
      expect(futureRoot.listSync(), hasLength(2));
    },
  );

  test(
    'TC-372-08 legacy projection lazy adoption rebind and future rollback remain safe',
    () async {
      final root = await Directory.systemTemp.createTemp('ledger-372-08-');
      addTearDown(() => root.delete(recursive: true));
      final bindingA = _binding('e');
      final bindingB = _binding('f');
      final legacyOwner = File(
        '${root.path}${Platform.pathSeparator}1042.owner',
      )..writeAsStringSync(_digest('9'), flush: true);
      final legacyContent =
          File('${root.path}${Platform.pathSeparator}1042.content-kind')
            ..writeAsStringSync(
              '{"v":1,"kind":"message","event":"opaque",'
              '"generation":"legacy-generation"}',
              flush: true,
            );
      final ownerBytes = legacyOwner.readAsBytesSync();
      final originalContentBytes = legacyContent.readAsBytesSync();
      final store = LocalNotificationLedgerStore(directory: root);
      await store.initializeOrRebind(currentOpaqueBinding: bindingA);

      final directEvent = _digest('5');
      final groupEvent = _digest('6');
      final adopted = await store.mutate(
        currentOpaqueBinding: bindingA,
        mutation: (current) => current.copyWith(
          storeRevision: current.storeRevision + 1,
          records: <String, LocalNotificationRecordV1>{
            directEvent: _readyRecord(
              eventCorrelation: directEvent,
              conversationDigest: _digest('1'),
              contentGeneration: 'legacy-generation',
            ),
            groupEvent: _readyRecord(
              eventCorrelation: groupEvent,
              conversationDigest: _digest('2'),
              producerKind: LocalNotificationProducerKind.groupReaction,
              contentGeneration: 'group-generation',
            ),
          },
        ),
      );
      expect(adopted?.records, hasLength(2));
      expect(
        adopted?.records[directEvent]?.conversationDigest,
        isNot(adopted?.records[groupEvent]?.conversationDigest),
        reason: 'direct/group authorities remain digest-isolated',
      );

      legacyContent.writeAsStringSync(
        '{"v":1,"kind":"message","event":"opaque",'
        '"generation":"old-build-replacement"}',
        flush: true,
      );
      final reopened = await store.read(currentOpaqueBinding: bindingA);
      expect(
        reopened?.records[directEvent]?.contentGeneration,
        isNot(contains('old-build-replacement')),
        reason: 'a legacy overwrite is detected, never assumed adopted',
      );
      expect(legacyOwner.readAsBytesSync(), ownerBytes);
      expect(legacyContent.readAsBytesSync(), isNot(originalContentBytes));

      final beforeForeignRead = store.ledgerFile.readAsBytesSync();
      expect(await store.read(currentOpaqueBinding: bindingB), isNull);
      expect(store.ledgerFile.readAsBytesSync(), beforeForeignRead);

      final rebound = await store.initializeOrRebind(
        currentOpaqueBinding: bindingB,
      );
      expect(rebound?.records, isEmpty);
      expect(legacyOwner.readAsBytesSync(), ownerBytes);
      expect(
        legacyContent.readAsStringSync(),
        contains('old-build-replacement'),
      );

      const futureBytes = '{"schemaVersion":99,"rollback":"opaque"}';
      store.ledgerFile.writeAsStringSync(futureBytes, flush: true);
      expect(await store.read(currentOpaqueBinding: bindingB), isNull);
      expect(
        await store.initializeOrRebind(currentOpaqueBinding: bindingB),
        isNull,
      );
      expect(store.ledgerFile.readAsStringSync(), futureBytes);
      expect(legacyOwner.readAsBytesSync(), ownerBytes);
    },
  );
}

String get fileSeparatorMarker =>
    '${Platform.pathSeparator}${LocalNotificationLedgerStore.fileName}';

Map<String, Object?> _patched(
  Map<String, Object?> template,
  Map<Object?, Object?> patch,
) {
  return <String, Object?>{
    ...template,
    for (final entry in patch.entries) entry.key! as String: entry.value,
  };
}

LocalNotificationRecordV1 _record(Map<String, Object?> value) {
  return LocalNotificationRecordV1(
    eventCorrelation: value['eventCorrelation']! as String,
    conversationDigest: value['conversationDigest']! as String,
    producerKind: _enumByWireName(
      LocalNotificationProducerKind.values,
      value['producerKind'],
      (value) => value.wireName,
    ),
    sourceCustody: _enumByWireName(
      LocalNotificationSourceCustody.values,
      value['sourceCustody'],
      (value) => value.wireName,
    ),
    readState: _enumByWireName(
      LocalNotificationReadState.values,
      value['readState'],
      (value) => value.wireName,
    ),
    presentationState: _enumByWireName(
      LocalNotificationPresentationState.values,
      value['presentationState'],
      (value) => value.wireName,
    ),
    presentationOwner: _enumByWireName(
      LocalNotificationPresentationOwner.values,
      value['presentationOwner'],
      (value) => value.wireName,
    ),
    notificationId: value['notificationId'] as int?,
    contentGeneration: value['contentGeneration'] as String?,
    lastEvaluatedLifecycle: _enumByWireName(
      LocalNotificationEvaluatedLifecycle.values,
      value['lastEvaluatedLifecycle'],
      (value) => value.wireName,
    ),
    visibilityRevision: value['visibilityRevision'] as int?,
    lifecycleGeneration: value['lifecycleGeneration'] as int?,
    effectPhase: _enumByWireName(
      LocalNotificationEffectPhase.values,
      value['effectPhase'],
      (value) => value.wireName,
    ),
    attemptKind: value['attemptKind'] == null
        ? null
        : _enumByWireName<LocalNotificationAttemptKind>(
            LocalNotificationAttemptKind.values,
            value['attemptKind'],
            (value) => value.wireName,
          ),
    effectToken: value['effectToken'] as String?,
    revision: value['revision']! as int,
    createdAtUtc: value['createdAtUtc']! as String,
    updatedAtUtc: value['updatedAtUtc']! as String,
    terminalAtUtc: value['terminalAtUtc'] as String?,
    settledAtUtc: value['settledAtUtc'] as String?,
  );
}

T _enumByWireName<T>(
  List<T> values,
  Object? raw,
  String Function(T value) wireName,
) {
  return values.singleWhere((value) => wireName(value) == raw);
}

Map<String, Object?> _deepCopy(Map<String, Object?> value) {
  return Map<String, Object?>.from(jsonDecode(jsonEncode(value))! as Map);
}

void _writePath(Map<String, Object?> root, String path, Object? value) {
  final components = path.split('.');
  Map<String, Object?> cursor = root;
  for (final component in components.take(components.length - 1)) {
    cursor = Map<String, Object?>.from(cursor[component]! as Map);
    Map<String, Object?> parent = root;
    for (final ancestor in components.takeWhile((part) => part != component)) {
      parent = parent[ancestor]! as Map<String, Object?>;
    }
    parent[component] = cursor;
  }

  Map<String, Object?> destination = root;
  for (final component in components.take(components.length - 1)) {
    destination = destination[component]! as Map<String, Object?>;
  }
  destination[components.last] = value;
}

String _binding(String character) => 'v1:${_digest(character)}';

String _digest(String character) => List<String>.filled(64, character).join();

LocalNotificationRecordV1 _readyRecord({
  required String eventCorrelation,
  required String conversationDigest,
  LocalNotificationProducerKind producerKind =
      LocalNotificationProducerKind.directMessage,
  String contentGeneration = 'generation-7',
}) {
  return LocalNotificationRecordV1(
    eventCorrelation: eventCorrelation,
    conversationDigest: conversationDigest,
    producerKind: producerKind,
    sourceCustody: LocalNotificationSourceCustody.sqlReady,
    readState: LocalNotificationReadState.unread,
    presentationState: LocalNotificationPresentationState.notEvaluated,
    presentationOwner: LocalNotificationPresentationOwner.mainApp,
    notificationId: 1042,
    contentGeneration: contentGeneration,
    lastEvaluatedLifecycle: LocalNotificationEvaluatedLifecycle.background,
    visibilityRevision: 7,
    lifecycleGeneration: 11,
    effectPhase: LocalNotificationEffectPhase.ready,
    attemptKind: null,
    effectToken: null,
    revision: 1,
    createdAtUtc: '2026-08-01T10:00:00.000Z',
    updatedAtUtc: '2026-08-01T10:00:00.000Z',
    terminalAtUtc: null,
    settledAtUtc: null,
  );
}

LocalNotificationRecordV1 _settledRecord({
  required String eventCorrelation,
  required String conversationDigest,
  required String terminalAtUtc,
  required String settledAtUtc,
}) {
  return _readyRecord(
    eventCorrelation: eventCorrelation,
    conversationDigest: conversationDigest,
  ).copyWith(
    presentationState: LocalNotificationPresentationState.osPosted,
    effectPhase: LocalNotificationEffectPhase.settled,
    revision: 5,
    updatedAtUtc: settledAtUtc,
    terminalAtUtc: terminalAtUtc,
    settledAtUtc: settledAtUtc,
  );
}
