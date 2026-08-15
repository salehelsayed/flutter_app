import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/app_root_notification_open.dart';
import 'package:flutter_app/core/notifications/app_visibility_route_binding.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/notifications/notification_open_dedupe_gate.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';

void main() {
  group('app-root notification open', () {
    late _AppRootNotificationHarness harness;

    setUp(() {
      harness = _AppRootNotificationHarness();
    });

    test(
      'warm remote push prepares conversation target before route',
      () async {
        await routeAppRootRemoteNotificationOpen(
          data: const <String, dynamic>{
            'type': 'new_message',
            'sender_id': 'peer-123',
          },
          onBeforeOpen: harness.clear,
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.route,
          onMissingRouteTarget: harness.missing,
        );

        expect(harness.events, <String>[
          'clear',
          'prepare:peer-123',
          'route:peer-123',
        ]);
        expect(
          harness.routed.single.kind,
          NotificationRouteTargetKind.conversation,
        );
        expect(harness.routed.single.peerId, 'peer-123');
        expect(harness.missingCalls, 0);
      },
    );

    test(
      'terminated local notification launch prepares group target before route',
      () async {
        await routeAppRootInitialLocalNotificationOpen(
          consumeInitialPayload: () async => 'group:group-123|message:msg-123',
          onBeforeOpen: harness.clear,
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.route,
        );

        expect(harness.events, <String>[
          'clear',
          'prepare:group:group-123|message:msg-123',
          'route:group:group-123|message:msg-123',
        ]);
        expect(harness.routed.single.kind, NotificationRouteTargetKind.group);
        expect(harness.routed.single.groupId, 'group-123');
        expect(harness.routed.single.messageId, 'msg-123');
      },
    );

    test(
      'ordinary terminated launch does not run notification target callbacks',
      () async {
        await routeAppRootInitialLocalNotificationOpen(
          consumeInitialPayload: () async => null,
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.route,
        );

        expect(harness.events, isEmpty);
        expect(harness.routed, isEmpty);
      },
    );

    test(
      'deferred initial-local direct and group success hand off exact targets',
      () async {
        final tappedAt = DateTime.utc(2026, 7, 13, 4, 28, 46);
        final coordinator = NotificationOpenRouteCoordinator();
        var offset = 0;
        for (final target in <NotificationRouteTarget>[
          const NotificationRouteTarget.conversation('peer-direct'),
          const NotificationRouteTarget.group(
            'group-discussion',
            messageId: 'message-1',
          ),
        ]) {
          final context = coordinator.createContext(
            routeTarget: target,
            tappedAt: tappedAt.add(Duration(seconds: offset++)),
          );
          final dispatch = await _deferContext(coordinator, context);

          expect(
            dispatch.disposition,
            NotificationOpenRouteDisposition.deferred,
          );
          expect(coordinator.deferred, same(context));
          var completionDelivered = false;
          dispatch.completion.then((_) => completionDelivered = true);
          await Future<void>.delayed(Duration.zero);
          expect(
            completionDelivered,
            isFalse,
            reason: 'startup must continue before deferred routing completes',
          );

          NotificationOpenRouteContext? routed;
          final attempt = await coordinator.runDeferredAttempt(
            maxAttempts: 2,
            onRouteContext: (value) async {
              expect(coordinator.active, same(value));
              routed = value;
              return NotificationOpenRouteDisposition.routed;
            },
          );
          final completion = await dispatch.completion;

          expect(routed, same(context));
          expect(routed!.routeTarget, same(target));
          expect(routed!.tappedAt, context.tappedAt);
          expect(attempt.status, NotificationOpenDeferredAttemptStatus.routed);
          expect(
            completion.status,
            NotificationOpenRouteCompletionStatus.routed,
          );
          expect(coordinator.active, isNull);
          expect(coordinator.deferred, isNull);
        }
      },
    );

    test(
      'deferred failure is retained once then completes as a value without an uncaught error',
      () async {
        final coordinator = NotificationOpenRouteCoordinator();
        final context = coordinator.createContext(
          routeTarget: const NotificationRouteTarget.conversation('peer-a'),
          tappedAt: DateTime.utc(2026, 7, 13, 4, 28, 46),
        );
        final failure = StateError('deferred route failed');
        final dispatch = await _deferContext(coordinator, context);

        final first = await coordinator.runDeferredAttempt(
          maxAttempts: 2,
          onRouteContext: (_) async => throw failure,
        );
        expect(first.status, NotificationOpenDeferredAttemptStatus.retry);
        expect(first.attempt, 1);
        expect(first.error, same(failure));
        expect(coordinator.deferred, same(context));

        var completionDelivered = false;
        dispatch.completion.then((_) => completionDelivered = true);
        await Future<void>.delayed(Duration.zero);
        expect(completionDelivered, isFalse);

        final second = await coordinator.runDeferredAttempt(
          maxAttempts: 2,
          onRouteContext: (_) async => throw failure,
        );
        final completion = await dispatch.completion;

        expect(second.status, NotificationOpenDeferredAttemptStatus.failed);
        expect(second.attempt, 2);
        expect(completion.status, NotificationOpenRouteCompletionStatus.failed);
        expect(completion.error, same(failure));
        expect(coordinator.active, isNull);
        expect(coordinator.deferred, isNull);
      },
    );

    test(
      'concurrent deferred flushes join one handler invocation and consume one attempt',
      () async {
        final coordinator = NotificationOpenRouteCoordinator();
        final context = coordinator.createContext(
          routeTarget: const NotificationRouteTarget.conversation('peer-one'),
          tappedAt: DateTime.utc(2026, 7, 13, 4, 28, 46),
        );
        final dispatch = await _deferContext(coordinator, context);
        final attemptStarted = Completer<void>();
        final releaseAttempt = Completer<void>();
        var handlerCalls = 0;

        final first = coordinator.runDeferredAttempt(
          maxAttempts: 2,
          onRouteContext: (_) async {
            handlerCalls += 1;
            attemptStarted.complete();
            await releaseAttempt.future;
            return NotificationOpenRouteDisposition.routed;
          },
        );
        await attemptStarted.future;
        final joined = coordinator.runDeferredAttempt(
          maxAttempts: 2,
          onRouteContext: (_) async {
            fail('a joined flush must not invoke a second handler');
          },
        );

        expect(joined, same(first));
        expect(handlerCalls, 1);
        releaseAttempt.complete();
        final firstResult = await first;
        final joinedResult = await joined;

        expect(joinedResult, same(firstResult));
        expect(firstResult.attempt, 1);
        expect(
          firstResult.status,
          NotificationOpenDeferredAttemptStatus.routed,
        );
        expect(handlerCalls, 1);
        expect(
          (await dispatch.completion).status,
          NotificationOpenRouteCompletionStatus.routed,
        );
        expect(coordinator.deferred, isNull);
      },
    );

    test(
      'deferred retry scheduler lets only the newest exact ordinal own and fire',
      () {
        final timers = <_ManualTimer>[];
        final scheduler = NotificationOpenDeferredRetryScheduler(
          createTimer: (_, callback) {
            final timer = _ManualTimer(callback);
            timers.add(timer);
            return timer;
          },
        );
        var olderRetries = 0;
        var newerRetries = 0;

        expect(
          scheduler.schedule(
            ownerOrdinal: 1,
            delay: const Duration(seconds: 1),
            onRetry: () => olderRetries += 1,
          ),
          isTrue,
        );
        expect(
          scheduler.schedule(
            ownerOrdinal: 1,
            delay: const Duration(seconds: 1),
            onRetry: () => olderRetries += 1,
          ),
          isFalse,
          reason: 'joined results must not reschedule the same owner',
        );
        expect(
          scheduler.schedule(
            ownerOrdinal: 2,
            delay: const Duration(seconds: 1),
            onRetry: () => newerRetries += 1,
          ),
          isTrue,
        );

        expect(timers, hasLength(2));
        expect(timers.first.isActive, isFalse);
        expect(scheduler.ownerOrdinal, 2);
        expect(scheduler.cancelIfOwnedBy(1), isFalse);
        timers.first.fire();
        expect(olderRetries, 0);
        timers.last.fire();
        expect(newerRetries, 1);
        expect(scheduler.ownerOrdinal, isNull);
        expect(scheduler.isScheduled, isFalse);
      },
    );

    test(
      'reverse preparation completion cannot let an older tap replace newer',
      () async {
        final coordinator = NotificationOpenRouteCoordinator();
        final tappedAt = DateTime.utc(2026, 7, 13, 4, 28, 46);
        final older = coordinator.createContext(
          routeTarget: const NotificationRouteTarget.group('group-a'),
          tappedAt: tappedAt,
        );
        final newer = coordinator.createContext(
          routeTarget: const NotificationRouteTarget.conversation('peer-b'),
          tappedAt: tappedAt,
        );
        final olderPreparation = Completer<void>();
        final newerPreparation = Completer<void>();

        Future<NotificationOpenRouteDispatch> finishPreparation(
          NotificationOpenRouteContext context,
          Completer<void> gate,
        ) async {
          await gate.future;
          return _deferContext(coordinator, context);
        }

        final olderFuture = finishPreparation(older, olderPreparation);
        final newerFuture = finishPreparation(newer, newerPreparation);
        newerPreparation.complete();
        final newerDispatch = await newerFuture;
        expect(coordinator.deferred, same(newer));

        olderPreparation.complete();
        final olderDispatch = await olderFuture;

        expect(older.ordinal, lessThan(newer.ordinal));
        expect(
          olderDispatch.disposition,
          NotificationOpenRouteDisposition.superseded,
        );
        expect(
          (await olderDispatch.completion).status,
          NotificationOpenRouteCompletionStatus.superseded,
        );
        expect(
          newerDispatch.disposition,
          NotificationOpenRouteDisposition.deferred,
        );
        expect(coordinator.deferred, same(newer));
      },
    );

    test(
      'older remote keeps its ordinal across slow side effects when newer local finishes first',
      () async {
        final coordinator = NotificationOpenRouteCoordinator();
        const remoteData = <String, dynamic>{
          'type': 'new_message',
          'sender_id': 'peer-remote-old',
          'message_id': 'message-remote-old',
        };
        final remoteTarget = NotificationRouteTarget.fromRemoteMessageData(
          remoteData,
        )!;
        final remoteContext = coordinator.createContext(
          routeTarget: remoteTarget,
          tappedAt: DateTime.utc(2026, 7, 13, 4, 28, 46),
        );
        final remoteSideEffectStarted = Completer<void>();
        final releaseRemoteSideEffect = Completer<void>();
        NotificationOpenRouteDispatch? remoteDispatch;

        final remoteOpen = routeAppRootRemoteNotificationOpen(
          data: remoteData,
          prevalidatedRouteTarget: remoteContext.routeTarget,
          onBeforeRouteTarget: (target) async {
            expect(target, same(remoteContext.routeTarget));
            remoteSideEffectStarted.complete();
            await releaseRemoteSideEffect.future;
          },
          onRouteTarget: (_) async {
            remoteDispatch = await _deferContext(coordinator, remoteContext);
          },
          onMissingRouteTarget: () async =>
              fail('validated remote target must not be missing'),
        );
        await remoteSideEffectStarted.future;

        late NotificationOpenRouteContext localContext;
        late NotificationOpenRouteDispatch localDispatch;
        await routeAppRootLocalNotificationTap(
          payload: 'peer-local-new',
          onBeforeRouteTarget: (target) async {
            localContext = coordinator.createContext(
              routeTarget: target,
              tappedAt: DateTime.utc(2026, 7, 13, 4, 29),
            );
          },
          onRouteTarget: (_) async {
            localDispatch = await _deferContext(coordinator, localContext);
          },
        );
        expect(coordinator.deferred, same(localContext));

        releaseRemoteSideEffect.complete();
        await remoteOpen;

        expect(remoteContext.ordinal, lessThan(localContext.ordinal));
        expect(
          remoteDispatch!.disposition,
          NotificationOpenRouteDisposition.superseded,
        );
        expect(coordinator.deferred, same(localContext));
        coordinator.cancelDeferred();
        await localDispatch.completion;
      },
    );

    test(
      'newer remote wins when older local preparation completes in reverse order',
      () async {
        final coordinator = NotificationOpenRouteCoordinator();
        final localPreparationStarted = Completer<void>();
        final releaseLocalPreparation = Completer<void>();
        late NotificationOpenRouteContext localContext;
        NotificationOpenRouteDispatch? localDispatch;

        final localOpen = routeAppRootLocalNotificationTap(
          payload: 'peer-local-old',
          onBeforeRouteTarget: (target) async {
            localContext = coordinator.createContext(
              routeTarget: target,
              tappedAt: DateTime.utc(2026, 7, 13, 4, 28, 46),
            );
            localPreparationStarted.complete();
            await releaseLocalPreparation.future;
          },
          onRouteTarget: (_) async {
            localDispatch = await _deferContext(coordinator, localContext);
          },
        );
        await localPreparationStarted.future;

        const remoteData = <String, dynamic>{
          'type': 'new_message',
          'sender_id': 'peer-remote-new',
          'message_id': 'message-remote-new',
        };
        final remoteTarget = NotificationRouteTarget.fromRemoteMessageData(
          remoteData,
        )!;
        final remoteContext = coordinator.createContext(
          routeTarget: remoteTarget,
          tappedAt: DateTime.utc(2026, 7, 13, 4, 29),
        );
        late NotificationOpenRouteDispatch remoteDispatch;
        await routeAppRootRemoteNotificationOpen(
          data: remoteData,
          prevalidatedRouteTarget: remoteContext.routeTarget,
          onBeforeRouteTarget: (_) async {},
          onRouteTarget: (_) async {
            remoteDispatch = await _deferContext(coordinator, remoteContext);
          },
          onMissingRouteTarget: () async =>
              fail('validated remote target must not be missing'),
        );
        expect(coordinator.deferred, same(remoteContext));

        releaseLocalPreparation.complete();
        await localOpen;

        expect(localContext.ordinal, lessThan(remoteContext.ordinal));
        expect(
          localDispatch!.disposition,
          NotificationOpenRouteDisposition.superseded,
        );
        expect(coordinator.deferred, same(remoteContext));
        coordinator.cancelDeferred();
        await remoteDispatch.completion;
      },
    );

    test(
      'newer failed deferred route keeps its owned retry when older flush finishes late',
      () async {
        final coordinator = NotificationOpenRouteCoordinator();
        late _ManualTimer retryTimer;
        final retryScheduler = NotificationOpenDeferredRetryScheduler(
          createTimer: (_, callback) {
            retryTimer = _ManualTimer(callback);
            return retryTimer;
          },
        );
        final older = coordinator.createContext(
          routeTarget: const NotificationRouteTarget.conversation('peer-old'),
          tappedAt: DateTime.utc(2026, 7, 13, 4, 28, 46),
        );
        final olderDispatch = await _deferContext(coordinator, older);
        final attemptStarted = Completer<void>();
        final releaseFailure = Completer<void>();
        final failure = StateError('older flush failed');

        final olderAttempt = coordinator.runDeferredAttempt(
          maxAttempts: 2,
          onRouteContext: (_) async {
            attemptStarted.complete();
            await releaseFailure.future;
            throw failure;
          },
        );
        await attemptStarted.future;
        final joinedOlderAttempt = coordinator.runDeferredAttempt(
          maxAttempts: 2,
          onRouteContext: (_) async {
            fail('a concurrent waiter must join the older in-flight attempt');
          },
        );
        expect(joinedOlderAttempt, same(olderAttempt));

        final newer = coordinator.createContext(
          routeTarget: const NotificationRouteTarget.group(
            'group-new',
            messageId: 'message-new',
          ),
          tappedAt: DateTime.utc(2026, 7, 13, 4, 29, 12),
        );
        final newerDispatch = await _deferContext(coordinator, newer);
        expect(
          (await olderDispatch.completion).status,
          NotificationOpenRouteCompletionStatus.superseded,
        );
        expect(coordinator.deferred, same(newer));

        var newerAttemptCalls = 0;
        final newerFirstResult = await coordinator.runDeferredAttempt(
          maxAttempts: 2,
          onRouteContext: (_) async {
            newerAttemptCalls += 1;
            throw StateError('newer transient route failure');
          },
        );
        expect(
          newerFirstResult.status,
          NotificationOpenDeferredAttemptStatus.retry,
        );
        expect(newerFirstResult.attempt, 1);
        final newerRetryCompleted =
            Completer<NotificationOpenDeferredAttemptResult>();
        expect(
          retryScheduler.schedule(
            ownerOrdinal: newer.ordinal,
            delay: const Duration(seconds: 1),
            onRetry: () {
              unawaited(() async {
                try {
                  newerRetryCompleted.complete(
                    await coordinator.runDeferredAttempt(
                      maxAttempts: 2,
                      onRouteContext: (_) async {
                        newerAttemptCalls += 1;
                        return NotificationOpenRouteDisposition.routed;
                      },
                    ),
                  );
                } catch (error, stackTrace) {
                  newerRetryCompleted.completeError(error, stackTrace);
                }
              }());
            },
          ),
          isTrue,
        );
        expect(retryScheduler.ownerOrdinal, newer.ordinal);

        releaseFailure.complete();
        final olderResult = await olderAttempt;
        expect(await joinedOlderAttempt, same(olderResult));
        expect(olderResult.attempt, 1);
        expect(
          olderResult.status,
          NotificationOpenDeferredAttemptStatus.superseded,
        );
        expect(coordinator.deferred, same(newer));
        expect(
          retryScheduler.cancelIfOwnedBy(older.ordinal),
          isFalse,
          reason: 'the older terminal result cannot cancel the newer timer',
        );
        expect(retryScheduler.ownerOrdinal, newer.ordinal);

        retryTimer.fire();
        final newerResult = await newerRetryCompleted.future;
        expect(
          newerResult.status,
          NotificationOpenDeferredAttemptStatus.routed,
        );
        expect(newerResult.attempt, 2);
        expect(newerAttemptCalls, 2);
        expect(retryScheduler.ownerOrdinal, isNull);
        expect(
          (await newerDispatch.completion).status,
          NotificationOpenRouteCompletionStatus.routed,
        );
        expect(coordinator.deferred, isNull);
      },
    );

    test(
      'invalid warm local and remote opens cannot replace deferred state',
      () async {
        final coordinator = NotificationOpenRouteCoordinator();
        final pending = coordinator.createContext(
          routeTarget: const NotificationRouteTarget.group(
            'group-pending',
            messageId: 'message-pending',
          ),
          tappedAt: DateTime.utc(2026, 7, 13, 4, 28, 46),
        );
        await _deferContext(coordinator, pending);
        var prepareCalls = 0;
        var routeCalls = 0;
        var missingCalls = 0;

        Future<void> prepare(NotificationRouteTarget target) async {
          prepareCalls += 1;
          coordinator.defer(
            coordinator.createContext(
              routeTarget: target,
              tappedAt: DateTime.utc(2026, 7, 13, 5),
            ),
          );
        }

        Future<void> route(NotificationRouteTarget target) async {
          routeCalls += 1;
          final context = coordinator.createContext(
            routeTarget: target,
            tappedAt: DateTime.utc(2026, 7, 13, 5),
          );
          await coordinator.dispatch(
            context: context,
            onRouteContext: (_) async =>
                NotificationOpenRouteDisposition.routed,
          );
        }

        await routeAppRootLocalNotificationTap(
          payload: '   ',
          onBeforeRouteTarget: prepare,
          onRouteTarget: route,
        );
        await routeAppRootRemoteNotificationOpen(
          data: const <String, dynamic>{'type': 'unknown_type'},
          onBeforeRouteTarget: prepare,
          onRouteTarget: route,
          onMissingRouteTarget: () async => missingCalls += 1,
        );

        expect(prepareCalls, 0);
        expect(routeCalls, 0);
        expect(missingCalls, 1);
        expect(coordinator.active, isNull);
        expect(coordinator.deferred, same(pending));
      },
    );

    test(
      'remote dedupe commits only routed completion and releases failures',
      () {
        final gate = NotificationOpenDedupeGate();
        const data = <String, dynamic>{
          'type': 'new_message',
          'sender_id': 'peer-remote',
          'message_id': 'message-remote',
        };
        final failure = NotificationOpenRouteCompletion.failed(
          StateError('route failed'),
          StackTrace.current,
        );

        expect(gate.tryBegin(data), isTrue);
        gate.finish(
          data,
          success: didNotificationOpenRouteSucceed(
            routeTargetResolved: true,
            completion: failure,
          ),
        );
        expect(
          gate.tryBegin(data),
          isTrue,
          reason: 'a failed deferred route must remain retryable',
        );
        gate.finish(
          data,
          success: didNotificationOpenRouteSucceed(
            routeTargetResolved: true,
            completion: const NotificationOpenRouteCompletion.routed(),
          ),
        );
        expect(
          gate.tryBegin(data),
          isFalse,
          reason: 'only an actually routed open commits the dedupe entry',
        );
      },
    );

    test(
      'missing direct contact releases remote dedupe and a later tap succeeds after materialization',
      () async {
        final gate = NotificationOpenDedupeGate();
        final coordinator = NotificationOpenRouteCoordinator();
        const data = <String, dynamic>{
          'type': 'new_message',
          'sender_id': 'peer-materializing',
          'message_id': 'message-materializing',
        };
        Object? materializedContact;
        var routeCalls = 0;

        Future<bool> open() async {
          if (!gate.tryBegin(data)) return false;
          var routeSucceeded = false;
          try {
            final target = NotificationRouteTarget.fromRemoteMessageData(data)!;
            final context = coordinator.createContext(
              routeTarget: target,
              tappedAt: DateTime.utc(2026, 7, 13, 4, 28, 46),
            );
            NotificationOpenRouteCompletion completion;
            try {
              final dispatch = await coordinator.dispatch(
                context: context,
                onRouteContext: (_) async {
                  routeCalls += 1;
                  if (materializedContact == null) {
                    throw StateError(
                      'Notification conversation contact is not available yet.',
                    );
                  }
                  return NotificationOpenRouteDisposition.routed;
                },
              );
              completion = await dispatch.completion;
            } catch (error, stackTrace) {
              completion = NotificationOpenRouteCompletion.failed(
                error,
                stackTrace,
              );
            }
            routeSucceeded = didNotificationOpenRouteSucceed(
              routeTargetResolved: true,
              completion: completion,
            );
            return routeSucceeded;
          } finally {
            gate.finish(data, success: routeSucceeded);
          }
        }

        expect(await open(), isFalse);
        materializedContact = Object();
        expect(
          await open(),
          isTrue,
          reason: 'the failed first tap must not poison the dedupe gate',
        );
        expect(
          await open(),
          isFalse,
          reason: 'the successful retry is committed',
        );
        expect(routeCalls, 2);
      },
    );

    test(
      'warm local notification tap prepares conversation target before route',
      () async {
        await routeAppRootLocalNotificationTap(
          payload: 'peer-456',
          onBeforeOpen: harness.clear,
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.route,
        );

        expect(harness.events, <String>[
          'clear',
          'prepare:peer-456',
          'route:peer-456',
        ]);
        expect(
          harness.routed.single.kind,
          NotificationRouteTargetKind.conversation,
        );
        expect(harness.routed.single.peerId, 'peer-456');
      },
    );

    test(
      'warm local contact-request tap prepares contact-request target before route',
      () async {
        await routeAppRootLocalNotificationTap(
          payload: 'contact_request:peer-request-123',
          onBeforeOpen: harness.clear,
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.route,
        );

        expect(harness.events, <String>[
          'clear',
          'prepare:contact_request:peer-request-123',
          'route:contact_request:peer-request-123',
        ]);
        expect(
          harness.routed.single.kind,
          NotificationRouteTargetKind.contactRequest,
        );
        expect(harness.routed.single.peerId, 'peer-request-123');
      },
    );

    test(
      'warm remote contact-request push prepares contact-request target before route',
      () async {
        await routeAppRootRemoteNotificationOpen(
          data: const <String, dynamic>{
            'type': 'contact_request',
            'sender_id': 'peer-request-123',
          },
          onBeforeOpen: harness.clear,
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.route,
          onMissingRouteTarget: harness.missing,
        );

        expect(harness.events, <String>[
          'clear',
          'prepare:contact_request:peer-request-123',
          'route:contact_request:peer-request-123',
        ]);
        expect(
          harness.routed.single.kind,
          NotificationRouteTargetKind.contactRequest,
        );
        expect(harness.routed.single.peerId, 'peer-request-123');
      },
    );

    test(
      'missing warm remote route target skips prepare and calls missing handler',
      () async {
        await routeAppRootRemoteNotificationOpen(
          data: const <String, dynamic>{'type': 'unknown_type'},
          onBeforeOpen: harness.clear,
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.route,
          onMissingRouteTarget: harness.missing,
        );

        expect(harness.events, <String>['clear', 'missing']);
        expect(harness.routed, isEmpty);
        expect(harness.missingCalls, 1);
      },
    );

    test(
      'missing group id on warm remote group push emits dedicated hook before missing handler',
      () async {
        await routeAppRootRemoteNotificationOpen(
          data: const <String, dynamic>{
            'kind': 'group_message',
            'message_id': 'msg-missing-group',
          },
          onBeforeOpen: harness.clear,
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.route,
          onMissingGroupRouteId: harness.missingGroupId,
          onMissingRouteTarget: harness.missing,
        );

        expect(harness.events, <String>[
          'clear',
          'missing-group-id',
          'missing',
        ]);
        expect(harness.routed, isEmpty);
        expect(harness.missingCalls, 1);
        expect(harness.missingGroupIdCalls, 1);
      },
    );

    test('route failure can finish the dedupe gate as retryable', () async {
      final gate = NotificationOpenDedupeGate();
      const data = <String, dynamic>{
        'type': 'group_message',
        'groupId': 'group-123',
        'message_id': 'msg-123',
      };

      expect(gate.tryBegin(data), isTrue);
      try {
        await routeAppRootRemoteNotificationOpenWithResult(
          data: data,
          onBeforeOpen: harness.clear,
          onBeforeRouteTarget: (_) async {
            throw StateError('prepare failed');
          },
          onRouteTarget: harness.route,
          onMissingRouteTarget: harness.missing,
        );
        fail('expected preparation failure');
      } catch (_) {
        gate.finish(data, success: false);
      }

      expect(gate.tryBegin(data), isTrue);
    });

    test('active group notification route can be skipped without stacking', () {
      final topRoute = _MutableTopRouteReader(
        AppVisibilityConversationIdentity.tryParse(
          lane: AppVisibilityConversationLane.group,
          value: 'group:group-123',
        ),
      );

      expect(
        isNotificationRouteTargetAlreadyActive(
          routeTarget: NotificationRouteTarget.group(
            'group-123',
            messageId: 'msg-123',
          ),
          appVisibilityRouteRegistry: topRoute,
        ),
        isTrue,
      );
      expect(
        isNotificationRouteTargetAlreadyActive(
          routeTarget: NotificationRouteTarget.group(
            'group-456',
            messageId: 'msg-123',
          ),
          appVisibilityRouteRegistry: topRoute,
        ),
        isFalse,
      );
      expect(
        isNotificationRouteTargetAlreadyActive(
          routeTarget: NotificationRouteTarget.conversation('peer-123'),
          appVisibilityRouteRegistry: topRoute,
        ),
        isFalse,
      );
    });

    // ── Report 139: 1:1 conversation already-active guard ────────────────
    // Mirrors the group guard above so a notification tap for a peer whose
    // conversation is already open does not push a second ConversationWired.
    test(
      'active 1:1 conversation route is skipped when its tracker is viewing that peer',
      () {
        final topRoute = _MutableTopRouteReader(
          AppVisibilityConversationIdentity.tryParse(
            lane: AppVisibilityConversationLane.direct,
            value: 'peer-123',
          ),
        );

        expect(
          isNotificationRouteTargetAlreadyActive(
            routeTarget: const NotificationRouteTarget.conversation('peer-123'),
            appVisibilityRouteRegistry: topRoute,
          ),
          isTrue,
        );
      },
    );

    test(
      '1:1 conversation route is NOT skipped for a different peer or a null tracker',
      () {
        final topRoute = _MutableTopRouteReader(
          AppVisibilityConversationIdentity.tryParse(
            lane: AppVisibilityConversationLane.direct,
            value: 'peer-123',
          ),
        );

        // Different peer than the one being viewed → still push (non-vacuity:
        // proves the GREEN above is peer-specific, not "always true").
        expect(
          isNotificationRouteTargetAlreadyActive(
            routeTarget: const NotificationRouteTarget.conversation('peer-999'),
            appVisibilityRouteRegistry: topRoute,
          ),
          isFalse,
        );

        // No top conversation → push, no crash.
        topRoute.current = null;
        expect(
          isNotificationRouteTargetAlreadyActive(
            routeTarget: const NotificationRouteTarget.conversation('peer-123'),
            appVisibilityRouteRegistry: topRoute,
          ),
          isFalse,
        );
      },
    );

    test(
      'group already-active guard is unchanged when the 1:1 tracker is also supplied',
      () {
        final topRoute = _MutableTopRouteReader(
          AppVisibilityConversationIdentity.tryParse(
            lane: AppVisibilityConversationLane.group,
            value: 'group:group-123',
          ),
        );

        expect(
          isNotificationRouteTargetAlreadyActive(
            routeTarget: const NotificationRouteTarget.group(
              'group-123',
              messageId: 'm',
            ),
            appVisibilityRouteRegistry: topRoute,
          ),
          isTrue,
        );
        expect(
          isNotificationRouteTargetAlreadyActive(
            routeTarget: const NotificationRouteTarget.group('group-456'),
            appVisibilityRouteRegistry: topRoute,
          ),
          isFalse,
        );
      },
    );

    test(
      'TC-371-03a backgrounded direct or group A tap before republish does not stack A',
      () {
        for (final target in const <NotificationRouteTarget>[
          NotificationRouteTarget.conversation('peer-a'),
          NotificationRouteTarget.group('group-a', messageId: 'message-a'),
        ]) {
          final lane = target.kind == NotificationRouteTargetKind.group
              ? AppVisibilityConversationLane.group
              : AppVisibilityConversationLane.direct;
          final topRoute = _MutableTopRouteReader(
            AppVisibilityConversationIdentity.tryParse(
              lane: lane,
              value: target.toPayload(),
            ),
          );

          // This process-local query deliberately has no freshness/lifecycle
          // input: background invalidation cannot make an already-stacked A
          // look absent before resume republishes its durable lease.
          expect(
            isNotificationRouteTargetAlreadyActive(
              routeTarget: target,
              appVisibilityRouteRegistry: topRoute,
            ),
            isTrue,
          );
        }
      },
    );

    test('TC-371-03b covered A is not top route and pop restores A', () {
      final directA = AppVisibilityConversationIdentity.tryParse(
        lane: AppVisibilityConversationLane.direct,
        value: 'peer-a',
      );
      final topRoute = _MutableTopRouteReader(directA);
      const target = NotificationRouteTarget.conversation('peer-a');

      expect(
        isNotificationRouteTargetAlreadyActive(
          routeTarget: target,
          appVisibilityRouteRegistry: topRoute,
        ),
        isTrue,
      );
      topRoute.current = null; // non-chat cover
      expect(
        isNotificationRouteTargetAlreadyActive(
          routeTarget: target,
          appVisibilityRouteRegistry: topRoute,
        ),
        isFalse,
      );
      topRoute.current = directA; // pop restores the underlying route
      expect(
        isNotificationRouteTargetAlreadyActive(
          routeTarget: target,
          appVisibilityRouteRegistry: topRoute,
        ),
        isTrue,
      );
    });
  });
}

final class _MutableTopRouteReader implements AppVisibilityTopRouteReader {
  _MutableTopRouteReader(this.current);

  AppVisibilityConversationIdentity? current;

  @override
  AppVisibilityConversationIdentity? get currentTopConversation => current;

  @override
  bool isCurrentTopConversation(AppVisibilityConversationIdentity identity) =>
      current == identity;

  @override
  bool isCurrentTopConversationValue({
    required AppVisibilityConversationLane lane,
    required String value,
  }) {
    final identity = AppVisibilityConversationIdentity.tryParse(
      lane: lane,
      value: value,
    );
    return identity != null && isCurrentTopConversation(identity);
  }
}

class _ManualTimer implements Timer {
  _ManualTimer(this._callback);

  final void Function() _callback;
  bool _isActive = true;
  int _tick = 0;

  @override
  bool get isActive => _isActive;

  @override
  int get tick => _tick;

  @override
  void cancel() {
    _isActive = false;
  }

  void fire() {
    if (!_isActive) return;
    _isActive = false;
    _tick += 1;
    _callback();
  }
}

class _AppRootNotificationHarness {
  final List<String> events = <String>[];
  final List<NotificationRouteTarget> routed = <NotificationRouteTarget>[];
  int missingCalls = 0;
  int missingGroupIdCalls = 0;

  Future<void> prepare(NotificationRouteTarget routeTarget) async {
    events.add('prepare:${routeTarget.toPayload()}');
  }

  Future<void> clear() async {
    events.add('clear');
  }

  Future<void> route(NotificationRouteTarget routeTarget) async {
    events.add('route:${routeTarget.toPayload()}');
    routed.add(routeTarget);
  }

  Future<void> missing() async {
    missingCalls += 1;
    events.add('missing');
  }

  Future<void> missingGroupId(Map<String, dynamic> data) async {
    missingGroupIdCalls += 1;
    events.add('missing-group-id');
  }
}

Future<NotificationOpenRouteDispatch> _deferContext(
  NotificationOpenRouteCoordinator coordinator,
  NotificationOpenRouteContext context,
) {
  return coordinator.dispatch(
    context: context,
    onRouteContext: (value) async => coordinator.defer(value)
        ? NotificationOpenRouteDisposition.deferred
        : NotificationOpenRouteDisposition.superseded,
  );
}
