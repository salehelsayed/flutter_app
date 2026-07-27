import 'dart:async';
import 'dart:io';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_exit_diagnosing_processor.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_runner.dart';
import 'package:flutter_app/features/groups/application/group_exit_release_diagnostics.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_diagnostic.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_intent.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_exit_diagnostic_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _DiagnosticRepository implements GroupExitDiagnosticRepository {
  final List<List<GroupExitDiagnostic>> batches = <List<GroupExitDiagnostic>>[];
  Future<void> Function(List<GroupExitDiagnostic>)? appendBehavior;

  @override
  Future<void> appendOutcome(List<GroupExitDiagnostic> diagnostics) {
    batches.add(diagnostics);
    return appendBehavior?.call(diagnostics) ?? Future<void>.value();
  }

  @override
  Future<void> clear() async => batches.clear();

  @override
  Future<List<GroupExitDiagnostic>> loadForAction({
    required String groupId,
    required String intentId,
  }) async => const <GroupExitDiagnostic>[];

  @override
  Future<List<GroupExitDiagnostic>> loadNewest() async =>
      batches.expand((batch) => batch).toList(growable: false);
}

class _ExecutionProcessor
    implements GroupExitIntentProcessor, GroupExitIntentExecutionProcessor {
  late GroupExitIntentProcessExecution execution;
  Map<String, GroupExitIntentProcessResult> allResult =
      <String, GroupExitIntentProcessResult>{};
  int executeCalls = 0;
  int normalGroupCalls = 0;
  int allCalls = 0;
  Object? executeError;
  StackTrace? executeStackTrace;
  Object? allError;
  StackTrace? allStackTrace;

  @override
  Future<GroupExitIntentProcessExecution> executeGroup(
    String groupId, {
    bool drainRoleBroadcasts = true,
    GroupExitIntent? knownIntent,
  }) async {
    executeCalls++;
    final failure = executeError;
    if (failure != null) {
      Error.throwWithStackTrace(failure, executeStackTrace!);
    }
    return execution;
  }

  @override
  Future<GroupExitIntentProcessAllExecution> executeAll() async =>
      GroupExitIntentProcessAllExecution.result(allResult);

  @override
  Future<Map<String, GroupExitIntentProcessResult>> processAll() async {
    allCalls++;
    final failure = allError;
    if (failure != null) {
      Error.throwWithStackTrace(failure, allStackTrace!);
    }
    return allResult;
  }

  @override
  Future<GroupExitIntentProcessResult> processGroup(
    String groupId, {
    bool drainRoleBroadcasts = true,
  }) async {
    normalGroupCalls++;
    return execution.replay();
  }
}

GroupExitIntent _intent() => GroupExitIntent(
  groupId: 'group-1',
  intentId: 'intent-1',
  selfPeerId: 'peer-self',
  selfJoinedAt: DateTime.utc(2026, 7, 20),
  state: GroupExitIntentState.cleanupPending,
  pendingBroadcastId: 'pending-1',
  createdAt: DateTime.utc(2026, 7, 21, 8),
  updatedAt: DateTime.utc(2026, 7, 21, 8),
);

GroupExitDiagnosticObserver _observer(_DiagnosticRepository repository) =>
    GroupExitDiagnosticObserver(
      repository: repository,
      now: () => DateTime.utc(2026, 7, 21, 12),
    );

Future<void> _flushDetached() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test(
    'PB266-03 disjoint observers cover snapshot pre-intent and every processor path once',
    () async {
      final intent = _intent();
      final repository = _DiagnosticRepository();
      final mutableFacts = <GroupExitProcessDiagnosticFact>[
        const GroupExitProcessDiagnosticFact.noticePrepareFailed(),
        const GroupExitProcessDiagnosticFact.noticePrepareFailed(),
      ];
      final result = GroupExitIntentProcessResult.withDiagnosticFacts(
        status: GroupExitIntentProcessStatus.failed,
        intent: intent,
        diagnosticFacts: mutableFacts,
      );
      mutableFacts.clear();
      expect(result.diagnosticFacts, const <GroupExitProcessDiagnosticFact>[
        GroupExitProcessDiagnosticFact.noticePrepareFailed(),
      ]);
      expect(
        () => result.diagnosticFacts.add(
          const GroupExitProcessDiagnosticFact.unexpected(
            GroupExitDiagnosticPhase.notice,
          ),
        ),
        throwsUnsupportedError,
      );
      final inner = _ExecutionProcessor()
        ..execution = GroupExitIntentProcessExecution.result(
          result: result,
          intent: intent,
        );
      final processor = DiagnosingGroupExitIntentProcessor(
        inner: inner,
        observer: _observer(repository),
      );

      expect(await processor.processGroup(intent.groupId), same(result));
      expect(inner.executeCalls, 1);
      expect(inner.normalGroupCalls, 0);

      inner.allResult = <String, GroupExitIntentProcessResult>{
        intent.groupId: result,
      };
      expect((await processor.processAll())[intent.groupId], same(result));
      expect(inner.allCalls, 1);
      await _flushDetached();
      expect(repository.batches, hasLength(2));
      expect(
        repository.batches
            .expand((batch) => batch)
            .map((row) => row.publicCode),
        everyElement(GroupExitDiagnosticPublicCode.ex03),
      );

      var snapshotCalls = 0;
      var requestCalls = 0;
      final snapshotError = StateError('snapshot unavailable');
      final mutableRequestFacts = <GroupExitProcessDiagnosticFact>[
        const GroupExitProcessDiagnosticFact.authorityUnavailable(),
        const GroupExitProcessDiagnosticFact.authorityUnavailable(),
      ];
      final preIntentRequest = GroupExitIntentRequestResult.withDiagnosticFacts(
        status: GroupExitIntentRequestStatus.unavailable,
        diagnosticFacts: mutableRequestFacts,
      );
      mutableRequestFacts.clear();
      expect(
        preIntentRequest.diagnosticFacts,
        const <GroupExitProcessDiagnosticFact>[
          GroupExitProcessDiagnosticFact.authorityUnavailable(),
        ],
      );
      expect(
        () => preIntentRequest.diagnosticFacts.clear(),
        throwsUnsupportedError,
      );
      final adapter = DiagnosingGroupExitActionAdapter(
        resolveSnapshot: (_) async {
          snapshotCalls++;
          throw snapshotError;
        },
        requestLeaveInner: (_) async {
          requestCalls++;
          return preIntentRequest;
        },
        queueLeaveInner: (_) async =>
            GroupExitIntentRequestResult.withDiagnosticFacts(
              status: GroupExitIntentRequestStatus.queued,
              intent: intent,
              diagnosticFacts: const <GroupExitProcessDiagnosticFact>[
                GroupExitProcessDiagnosticFact.noticePrepareFailed(),
              ],
            ),
        retryInner: (_) async =>
            GroupExitIntentRequestResult.withDiagnosticFacts(
              status: GroupExitIntentRequestStatus.pendingRoleSync,
              diagnosticFacts: <GroupExitProcessDiagnosticFact>[
                GroupExitProcessDiagnosticFact.roleSyncFailed(),
              ],
            ),
        observer: _observer(repository),
      );

      await expectLater(
        adapter.loadSnapshot(intent.groupId),
        throwsA(snapshotError),
      );
      final preIntent = await adapter.requestLeave(intent.groupId);
      expect(preIntent.intent, isNull);
      final intentBearing = await adapter.queueLeaveWhenSyncCompletes(
        intent.groupId,
      );
      expect(intentBearing.intent, same(intent));
      await adapter.retry(intent.groupId);
      await _flushDetached();

      expect(snapshotCalls, 1);
      expect(requestCalls, 1);
      // Two processor observations + snapshot EX01 + request EX01 + retry EX02.
      expect(repository.batches, hasLength(5));
      final lastThree = repository.batches
          .skip(2)
          .map((batch) => batch.single.publicCode)
          .toList(growable: false);
      expect(lastThree, <GroupExitDiagnosticPublicCode>[
        GroupExitDiagnosticPublicCode.ex01,
        GroupExitDiagnosticPublicCode.ex01,
        GroupExitDiagnosticPublicCode.ex02,
      ]);

      final mainSource = File('lib/main.dart').readAsStringSync();
      expect(
        RegExp(r'rawGroupExitIntentRunner').allMatches(mainSource),
        hasLength(2),
        reason: 'The raw runner may appear only at construction and as inner.',
      );
      expect(mainSource, contains('inner: rawGroupExitIntentRunner'));
      expect(
        mainSource,
        isNot(contains('processor: rawGroupExitIntentRunner')),
      );
      expect(mainSource, contains('processor: groupExitIntentProcessor'));
      expect(
        mainSource,
        contains('await groupExitIntentProcessor.processAll()'),
      );
      expect(
        RegExp(
          r'groupExitIntentProcessor\.processGroup\(groupId\)',
        ).allMatches(mainSource),
        hasLength(greaterThanOrEqualTo(3)),
      );
      expect(mainSource, contains('resolveSnapshot: groupExitActionAdapter'));
      expect(mainSource, contains('requestLeave: groupExitActionAdapter'));
      expect(
        mainSource,
        contains('queueLeaveInner: groupExitIntentCoordinator'),
      );
      expect(mainSource, contains('retry: groupExitActionAdapter.retry'));
      expect(mainSource, contains('runTypedGroupExitNativeLeave('));
      expect(mainSource, contains('throwGroupExitAuthorityFailure('));

      for (final path in const <String>[
        'lib/features/groups/presentation/screens/group_info_wired.dart',
        'lib/features/orbit/presentation/screens/orbit_wired.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(
          source,
          contains('resolveGroupExitActionSnapshot('),
          reason: '$path must enter through the application action boundary.',
        );
        expect(
          source,
          isNot(contains('resolveGroupExitActionSnapshotForPresentation(')),
          reason: '$path must not use the compatibility authority fallback.',
        );
        expect(source, isNot(contains('submitVoluntary(')));
        expect(source, isNot(contains('appendOutcome(')));
      }
    },
  );

  test('PB266-11 processor submits both warnings in one outcome', () async {
    final intent = _intent();
    final repository = _DiagnosticRepository();
    final result = GroupExitIntentProcessResult.withDiagnosticFacts(
      status: GroupExitIntentProcessStatus.completed,
      intent: intent,
      diagnosticFacts: const <GroupExitProcessDiagnosticFact>[
        GroupExitProcessDiagnosticFact.deliveryDegraded(),
        GroupExitProcessDiagnosticFact.rotationDeferred(),
      ],
    );
    final inner = _ExecutionProcessor()
      ..execution = GroupExitIntentProcessExecution.result(
        result: result,
        intent: intent,
      );
    final processor = DiagnosingGroupExitIntentProcessor(
      inner: inner,
      observer: _observer(repository),
    );

    expect(await processor.processGroup(intent.groupId), same(result));
    await _flushDetached();

    expect(repository.batches, hasLength(1));
    expect(
      repository.batches.single.map((row) => row.publicCode),
      <GroupExitDiagnosticPublicCode>[
        GroupExitDiagnosticPublicCode.ex08,
        GroupExitDiagnosticPublicCode.ex09,
      ],
    );
  });

  test(
    'PB266-04 pending or failed writer cannot retain exit authority or escape uncaught',
    () async {
      final previousFlowLogging = flowEventLoggingEnabled;
      flowEventLoggingEnabled = false;
      addTearDown(() => flowEventLoggingEnabled = previousFlowLogging);

      final intent = _intent();
      final repository = _DiagnosticRepository();
      final neverCompletes = Completer<void>();
      repository.appendBehavior = (_) => neverCompletes.future;
      final result = GroupExitIntentProcessResult.withDiagnosticFacts(
        status: GroupExitIntentProcessStatus.failed,
        intent: intent,
        diagnosticFacts: const <GroupExitProcessDiagnosticFact>[
          GroupExitProcessDiagnosticFact.cleanupIncomplete(),
        ],
      );
      final inner = _ExecutionProcessor()
        ..execution = GroupExitIntentProcessExecution.result(
          result: result,
          intent: intent,
        );
      final processor = DiagnosingGroupExitIntentProcessor(
        inner: inner,
        observer: _observer(repository),
      );

      expect(
        await processor
            .processGroup(intent.groupId)
            .timeout(const Duration(seconds: 1)),
        same(result),
      );
      expect(
        await processor
            .processGroup(intent.groupId)
            .timeout(const Duration(seconds: 1)),
        same(result),
      );
      expect(inner.executeCalls, 2);

      final originalError = StateError('original processor error');
      final originalStack = StackTrace.fromString('pb266-original-stack');
      inner.execution = GroupExitIntentProcessExecution.error(
        error: originalError,
        stackTrace: originalStack,
        intent: intent,
        diagnosticFacts: const <GroupExitProcessDiagnosticFact>[
          GroupExitProcessDiagnosticFact.unexpected(
            GroupExitDiagnosticPhase.notice,
          ),
        ],
      );
      Object? caughtError;
      StackTrace? caughtStack;
      try {
        await processor.processGroup(intent.groupId);
      } catch (error, stackTrace) {
        caughtError = error;
        caughtStack = stackTrace;
      }
      expect(caughtError, same(originalError));
      expect(caughtStack.toString(), contains('pb266-original-stack'));

      final thrownExecutionError = StateError('execution future escaped');
      inner
        ..executeError = thrownExecutionError
        ..executeStackTrace = StackTrace.fromString(
          'pb266-execution-future-stack',
        );
      caughtError = null;
      caughtStack = null;
      try {
        await processor.processGroup(intent.groupId);
      } catch (error, stackTrace) {
        caughtError = error;
        caughtStack = stackTrace;
      }
      expect(caughtError, same(thrownExecutionError));
      expect(caughtStack.toString(), contains('pb266-execution-future-stack'));
      inner
        ..executeError = null
        ..executeStackTrace = null;

      final aggregateError = StateError('aggregate future escaped');
      inner
        ..allError = aggregateError
        ..allStackTrace = StackTrace.fromString('pb266-aggregate-stack');
      caughtError = null;
      caughtStack = null;
      try {
        await processor.processAll();
      } catch (error, stackTrace) {
        caughtError = error;
        caughtStack = stackTrace;
      }
      expect(caughtError, same(aggregateError));
      expect(caughtStack.toString(), contains('pb266-aggregate-stack'));
      expect(inner.allCalls, 1);
      inner
        ..allError = null
        ..allStackTrace = null;

      // A synchronous writer throw is also contained by the detached observer.
      repository.appendBehavior = (_) => throw StateError('writer failed');
      inner.execution = GroupExitIntentProcessExecution.result(
        result: result,
        intent: intent,
      );
      expect(await processor.processGroup(intent.groupId), same(result));

      // Asynchronous writer and failure-telemetry errors are both contained in
      // the detached submission zone, even with flow logging disabled.
      final uncaught = <Object>[];
      repository.appendBehavior = (_) => Future<void>.error(
        StateError('async writer failed'),
        StackTrace.fromString('pb266-async-writer-stack'),
      );
      final errorContainedProcessor = DiagnosingGroupExitIntentProcessor(
        inner: inner,
        observer: GroupExitDiagnosticObserver(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 21, 12),
          onSubmissionFailure: () => throw StateError('telemetry failed'),
        ),
      );
      await runZonedGuarded(() async {
        expect(
          await errorContainedProcessor.processGroup(intent.groupId),
          same(result),
        );
        await _flushDetached();
      }, (error, _) => uncaught.add(error));
      expect(uncaught, isEmpty);
      expect(flowEventLoggingEnabled, isFalse);
    },
  );
}
