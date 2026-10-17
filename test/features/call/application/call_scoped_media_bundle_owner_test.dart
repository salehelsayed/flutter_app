import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/call/application/call_audio_controller.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_scoped_media_bundle_owner.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/infrastructure/bridge_call_media_protection_lease.dart';
import 'package:flutter_test/flutter_test.dart';

final _firstCallId = CallId.parse('11111111-1111-4111-8111-111111111111');
final _secondCallId = CallId.parse('22222222-2222-4222-8222-222222222222');
final _thirdCallId = CallId.parse('33333333-3333-4333-8333-333333333333');
final _now = DateTime.utc(2026, 8, 30, 12);

CallSessionSnapshot _snapshot(CallId callId) => CallSessionSnapshot.active(
  callId: callId,
  contactPeerId: 'contact',
  direction: CallDirection.outgoing,
  state: CallState.accepted,
  callerAccountPeerId: 'local-account',
  callerDeviceId: 'local-device',
  startedAt: _now,
  acceptedAt: _now,
);

Matcher _ownerFailure(CallScopedMediaBundleOwnerErrorCode code) =>
    isA<CallScopedMediaBundleOwnerException>().having(
      (error) => error.code,
      'code',
      code,
    );

void main() {
  test('a successor call waits for an earlier failed cleanup before taking '
      'the lease', () async {
    const negotiate = CallEffect(CallEffectType.startNegotiation);
    final lease = _ProtectionLease();
    var firstCloseAttempts = 0;
    var secondCreated = 0;
    final owner = CallScopedMediaBundleOwner(
      protection: lease,
      protectionRetryInterval: const Duration(milliseconds: 10),
      createBundle: (callId) {
        final harness = _BundleHarness(callId);
        if (callId != _firstCallId) {
          secondCreated++;
          return harness.value;
        }
        return CallScopedMediaBundle(
          callId: callId,
          engine: harness.engine,
          audioController: harness.audioController,
          negotiationExecutor: harness.executor,
          close: () async {
            if (++firstCloseAttempts == 1) {
              throw StateError('native media cleanup not confirmed');
            }
            await harness.audioController.close();
          },
        );
      },
    );
    addTearDown(owner.close);
    await owner.execute(negotiate, _snapshot(_firstCallId));
    await expectLater(owner.closeCall(_firstCallId), throwsStateError);

    final second = owner.execute(negotiate, _snapshot(_secondCallId));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(secondCreated, 0);
    expect(lease.log, <String>['acquire:1']);
    expect(lease.heldGeneration, 1);

    await owner.closeCall(_firstCallId);
    await second;
    expect(secondCreated, 1);
    expect(lease.log, <String>['acquire:1', 'release:1', 'acquire:2']);
    expect(lease.heldGeneration, 2);
  });

  test('a successor call cannot unprotect an earlier call whose media close '
      'is still pending', () async {
    const negotiate = CallEffect(CallEffectType.startNegotiation);
    final lease = _ProtectionLease();
    final firstCloseGate = Completer<void>();
    var firstNativeCloseConfirmed = false;
    var secondCreated = 0;
    final owner = CallScopedMediaBundleOwner(
      protection: lease,
      protectionRetryInterval: const Duration(milliseconds: 10),
      createBundle: (callId) {
        final harness = _BundleHarness(callId);
        if (callId != _firstCallId) {
          secondCreated++;
          return harness.value;
        }
        return CallScopedMediaBundle(
          callId: callId,
          engine: harness.engine,
          audioController: harness.audioController,
          negotiationExecutor: harness.executor,
          close: () async {
            await firstCloseGate.future;
            await harness.audioController.close();
            firstNativeCloseConfirmed = true;
          },
        );
      },
    );
    addTearDown(owner.close);
    await owner.execute(negotiate, _snapshot(_firstCallId));
    final firstClose = owner.closeCall(_firstCallId);

    final second = owner.execute(negotiate, _snapshot(_secondCallId));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(firstNativeCloseConfirmed, isFalse);
    expect(secondCreated, 0);
    expect(
      lease.heldGeneration,
      1,
      reason: 'the first call still owns live native media; log=${lease.log}',
    );

    firstCloseGate.complete();
    await firstClose;
    await second;
    expect(firstNativeCloseConfirmed, isTrue);
    expect(lease.log, <String>['acquire:1', 'release:1', 'acquire:2']);
    expect(lease.heldGeneration, 2);

    await owner.closeCall(_secondCallId);
    expect(lease.holder, isNull);
  });

  test('a waiting call that is retired does not drop an earlier pending '
      'close', () async {
    const negotiate = CallEffect(CallEffectType.startNegotiation);
    final lease = _ProtectionLease();
    final firstCloseGate = Completer<void>();
    var thirdCreated = 0;
    final owner = CallScopedMediaBundleOwner(
      protection: lease,
      protectionRetryInterval: const Duration(milliseconds: 10),
      createBundle: (callId) {
        final harness = _BundleHarness(callId);
        if (callId == _thirdCallId) thirdCreated++;
        if (callId != _firstCallId) return harness.value;
        return CallScopedMediaBundle(
          callId: callId,
          engine: harness.engine,
          audioController: harness.audioController,
          negotiationExecutor: harness.executor,
          close: () async {
            await firstCloseGate.future;
            await harness.audioController.close();
          },
        );
      },
    );
    addTearDown(owner.close);
    await owner.execute(negotiate, _snapshot(_firstCallId));
    final firstClose = owner.closeCall(_firstCallId);

    final second = owner.execute(negotiate, _snapshot(_secondCallId));
    final secondRetired = expectLater(
      second,
      throwsA(isA<CallScopedMediaBundleOwnerException>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await owner.closeCall(_secondCallId);
    await secondRetired;

    final third = owner.execute(negotiate, _snapshot(_thirdCallId));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(thirdCreated, 0);
    expect(
      lease.log,
      <String>['acquire:1'],
      reason:
          'the first call still '
          'owns live native media',
    );
    expect(lease.heldGeneration, 1);

    firstCloseGate.complete();
    await firstClose;
    await third;
    expect(thirdCreated, 1);
    expect(lease.log, <String>['acquire:1', 'release:1', 'acquire:2']);
    expect(lease.heldGeneration, 2);
  });

  test(
    'creates lazily and exposes audio only for the exact active call',
    () async {
      final bundles = <_BundleHarness>[];
      final owner = CallScopedMediaBundleOwner(
        createBundle: (callId) async {
          final bundle = _BundleHarness(callId);
          bundles.add(bundle);
          return bundle.value;
        },
      );
      addTearDown(owner.close);

      expect(
        await owner.execute(
          const CallEffect(CallEffectType.sendInvite),
          _snapshot(_firstCallId),
        ),
        isNull,
      );
      expect(bundles, isEmpty);
      expect(owner.currentAudioController(_firstCallId), isNull);
      expect(owner.currentAudioState(_firstCallId), isNull);

      await owner.execute(
        const CallEffect(CallEffectType.startNegotiation),
        _snapshot(_firstCallId),
      );
      await owner.execute(
        const CallEffect(CallEffectType.deliverAnswer),
        _snapshot(_firstCallId),
      );

      expect(bundles, hasLength(1));
      expect(bundles.single.executor.effects, <CallEffectType>[
        CallEffectType.startNegotiation,
        CallEffectType.deliverAnswer,
      ]);
      expect(
        owner.currentAudioController(_firstCallId),
        same(bundles.single.audioController),
      );
      expect(
        owner.currentAudioState(_firstCallId),
        same(bundles.single.audioController.state),
      );
      expect(owner.currentAudioController(_secondCallId), isNull);
      expect(owner.currentAudioState(_secondCallId), isNull);
    },
  );

  test(
    'publishes exact bundle availability for foreground audio binding',
    () async {
      late final _BundleHarness bundle;
      final owner = CallScopedMediaBundleOwner(
        createBundle: (callId) async {
          bundle = _BundleHarness(callId);
          return bundle.value;
        },
      );
      final changes = <CallScopedMediaBundle?>[];
      final subscription = owner.bundleChanges.listen(changes.add);
      addTearDown(subscription.cancel);
      addTearDown(owner.close);

      await owner.execute(
        const CallEffect(CallEffectType.startNegotiation),
        _snapshot(_firstCallId),
      );
      expect(changes, <CallScopedMediaBundle?>[bundle.value]);

      await owner.closeCall(_firstCallId);
      expect(changes, <CallScopedMediaBundle?>[bundle.value, null]);
    },
  );

  test(
    'fails closed with a redacted error while another call is creating',
    () async {
      final creationGate = Completer<void>();
      var factoryCalls = 0;
      final owner = CallScopedMediaBundleOwner(
        createBundle: (callId) async {
          factoryCalls++;
          await creationGate.future;
          return _BundleHarness(callId).value;
        },
      );
      addTearDown(owner.close);

      final firstExecution = owner.execute(
        const CallEffect(CallEffectType.startNegotiation),
        _snapshot(_firstCallId),
      );
      await Future<void>.delayed(Duration.zero);

      Object? mismatch;
      try {
        await owner.execute(
          const CallEffect(CallEffectType.startNegotiation),
          _snapshot(_secondCallId),
        );
      } catch (error) {
        mismatch = error;
      }
      expect(
        mismatch,
        _ownerFailure(CallScopedMediaBundleOwnerErrorCode.activeCallMismatch),
      );
      expect('$mismatch', isNot(contains(_firstCallId.value)));
      expect('$mismatch', isNot(contains(_secondCallId.value)));
      expect(factoryCalls, 1);

      creationGate.complete();
      await firstExecution;
    },
  );

  test(
    'cleans once, rejects stale effects, and creates a fresh next bundle',
    () async {
      final bundles = <_BundleHarness>[];
      final owner = CallScopedMediaBundleOwner(
        createBundle: (callId) async {
          final bundle = _BundleHarness(callId);
          bundles.add(bundle);
          return bundle.value;
        },
      );
      addTearDown(owner.close);

      await owner.execute(
        const CallEffect(CallEffectType.startNegotiation),
        _snapshot(_firstCallId),
      );
      await Future.wait<void>(<Future<void>>[
        owner.closeCall(_firstCallId),
        owner.closeCall(_firstCallId),
      ]);
      await owner.closeCall(_firstCallId);

      expect(bundles.single.closeCalls, 1);
      expect(owner.currentAudioController(_firstCallId), isNull);
      await expectLater(
        owner.execute(
          const CallEffect(CallEffectType.restartIce),
          _snapshot(_firstCallId),
        ),
        throwsA(_ownerFailure(CallScopedMediaBundleOwnerErrorCode.retiredCall)),
      );
      expect(bundles, hasLength(1));

      await owner.execute(
        const CallEffect(CallEffectType.startNegotiation),
        _snapshot(_secondCallId),
      );
      expect(bundles, hasLength(2));
      expect(bundles[1].engine, isNot(same(bundles[0].engine)));
      expect(
        bundles[1].audioController,
        isNot(same(bundles[0].audioController)),
      );
      expect(bundles[1].executor, isNot(same(bundles[0].executor)));
      await owner.closeCall(_secondCallId);
      expect(bundles[1].closeCalls, 1);
    },
  );

  test(
    'creation failure retires that call without blocking a later call',
    () async {
      var factoryCalls = 0;
      final secondBundle = _BundleHarness(_secondCallId);
      final owner = CallScopedMediaBundleOwner(
        createBundle: (callId) async {
          factoryCalls++;
          if (callId == _firstCallId) throw StateError('factory failed');
          return secondBundle.value;
        },
      );
      addTearDown(owner.close);

      await expectLater(
        owner.execute(
          const CallEffect(CallEffectType.startNegotiation),
          _snapshot(_firstCallId),
        ),
        throwsStateError,
      );
      await owner.closeCall(_firstCallId);
      await owner.closeCall(_firstCallId);
      await expectLater(
        owner.execute(
          const CallEffect(CallEffectType.startNegotiation),
          _snapshot(_firstCallId),
        ),
        throwsA(isA<CallScopedMediaBundleOwnerException>()),
      );

      await owner.execute(
        const CallEffect(CallEffectType.startNegotiation),
        _snapshot(_secondCallId),
      );
      expect(factoryCalls, 2);
      expect(secondBundle.executor.effects, <CallEffectType>[
        CallEffectType.startNegotiation,
      ]);
    },
  );

  test(
    'close failure stays fenced, coalesces retry, and succeeds exactly once',
    () async {
      final retryGate = Completer<void>();
      final bundles = <_BundleHarness>[];
      final owner = CallScopedMediaBundleOwner(
        createBundle: (callId) async {
          final bundle = _BundleHarness(
            callId,
            onCloseAttempt: (attempt) async {
              if (callId != _firstCallId) return;
              if (attempt == 1) throw StateError('close failed');
              if (attempt == 2) await retryGate.future;
            },
          );
          bundles.add(bundle);
          return bundle.value;
        },
      );
      addTearDown(owner.close);

      await owner.execute(
        const CallEffect(CallEffectType.startNegotiation),
        _snapshot(_firstCallId),
      );
      await expectLater(owner.closeCall(_firstCallId), throwsStateError);
      expect(bundles.single.closeCalls, 1);
      await expectLater(
        owner.execute(
          const CallEffect(CallEffectType.restartIce),
          _snapshot(_firstCallId),
        ),
        throwsA(_ownerFailure(CallScopedMediaBundleOwnerErrorCode.retiredCall)),
      );

      Object? retryFailure;
      var retryCompleted = false;
      final retries =
          Future.wait<void>(<Future<void>>[
            owner.closeCall(_firstCallId),
            owner.closeCall(_firstCallId),
          ]).then<void>(
            (_) => retryCompleted = true,
            onError: (Object error, StackTrace stackTrace) {
              retryFailure = error;
              retryCompleted = true;
            },
          );
      await Future<void>.delayed(Duration.zero);

      expect(bundles.single.closeCalls, 2);
      expect(retryCompleted, isFalse);
      retryGate.complete();
      await retries;
      expect(retryFailure, isNull);
      expect(retryCompleted, isTrue);

      await owner.closeCall(_firstCallId);
      expect(bundles.single.closeCalls, 2);

      await owner.execute(
        const CallEffect(CallEffectType.startNegotiation),
        _snapshot(_secondCallId),
      );
      expect(bundles, hasLength(2));
    },
  );

  test(
    'late-created bundle cleanup failure is never converted to success',
    () async {
      final creationGate = Completer<void>();
      final bundle = _BundleHarness(_firstCallId, failClose: true);
      final owner = CallScopedMediaBundleOwner(
        createBundle: (_) async {
          await creationGate.future;
          return bundle.value;
        },
      );
      addTearDown(owner.close);

      final execution = owner.execute(
        const CallEffect(CallEffectType.startNegotiation),
        _snapshot(_firstCallId),
      );
      await Future<void>.delayed(Duration.zero);
      final closing = owner.closeCall(_firstCallId);
      creationGate.complete();

      await expectLater(
        execution,
        throwsA(
          _ownerFailure(CallScopedMediaBundleOwnerErrorCode.cleanupFailed),
        ),
      );
      await expectLater(
        closing,
        throwsA(
          _ownerFailure(CallScopedMediaBundleOwnerErrorCode.cleanupFailed),
        ),
      );
      expect(bundle.closeCalls, 1);
    },
  );

  test('retired call tombstones stay at the fixed process bound', () async {
    final thirdCallId = CallId.parse('33333333-3333-4333-8333-333333333333');
    final bundles = <_BundleHarness>[];
    final owner = CallScopedMediaBundleOwner(
      retiredCallCapacity: 2,
      createBundle: (callId) async {
        final bundle = _BundleHarness(callId);
        bundles.add(bundle);
        return bundle.value;
      },
    );
    addTearDown(owner.close);

    for (final callId in <CallId>[_firstCallId, _secondCallId, thirdCallId]) {
      await owner.execute(
        const CallEffect(CallEffectType.startNegotiation),
        _snapshot(callId),
      );
      await owner.closeCall(callId);
    }

    await owner.execute(
      const CallEffect(CallEffectType.startNegotiation),
      _snapshot(_firstCallId),
    );
    expect(bundles, hasLength(4));
  });

  group('call-media protection lease', () {
    const negotiate = CallEffect(CallEffectType.startNegotiation);

    test(
      'is held before the media factory runs and released after the close',
      () async {
        final lease = _ProtectionLease();
        late final _BundleHarness bundle;
        final owner = CallScopedMediaBundleOwner(
          protection: lease,
          createBundle: (callId) async {
            lease.log.add('factory');
            bundle = _BundleHarness(
              callId,
              onCloseAttempt: (_) async => lease.log.add('close'),
            );
            return bundle.value;
          },
        );
        addTearDown(owner.close);

        await owner.execute(negotiate, _snapshot(_firstCallId));
        expect(lease.log, <String>['acquire:1', 'factory']);
        expect(lease.heldGeneration, 1);

        await owner.closeCall(_firstCallId);
        expect(lease.log, <String>[
          'acquire:1',
          'factory',
          'close',
          'release:1',
        ]);
        expect(lease.holder, isNull);
      },
    );

    test(
      "a first call closing late cannot clear the next call's hold",
      () async {
        final lease = _ProtectionLease();
        final firstClose = Completer<void>();
        var created = 0;
        final owner = CallScopedMediaBundleOwner(
          protection: lease,
          protectionRetryInterval: const Duration(milliseconds: 10),
          createBundle: (callId) async {
            created++;
            final gate = created == 1 ? firstClose : null;
            return _BundleHarness(
              callId,
              onCloseAttempt: gate == null ? null : (_) => gate.future,
            ).value;
          },
        );
        addTearDown(owner.close);

        await owner.execute(negotiate, _snapshot(_firstCallId));
        final closingFirst = owner.closeCall(_firstCallId);
        // The next call waits while the first call's close still holds the
        // lease, so the first release can never land on the next call's hold.
        final second = owner.execute(negotiate, _snapshot(_secondCallId));
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(lease.log, <String>['acquire:1']);
        expect(lease.heldGeneration, 1);

        firstClose.complete();
        await closingFirst;
        await second;
        expect(lease.log, <String>['acquire:1', 'release:1', 'acquire:2']);
        expect(lease.heldGeneration, 2);

        await owner.closeCall(_secondCallId);
        expect(lease.holder, isNull);
      },
    );

    test(
      'a failed media factory releases the generation it acquired',
      () async {
        final lease = _ProtectionLease();
        final owner = CallScopedMediaBundleOwner(
          protection: lease,
          createBundle: (_) => throw StateError('no engine'),
        );
        addTearDown(owner.close);

        await expectLater(
          owner.execute(negotiate, _snapshot(_firstCallId)),
          throwsStateError,
        );
        expect(lease.log, <String>['acquire:1', 'release:1']);
        expect(lease.holder, isNull);
      },
    );

    test('refused protection keeps the media factory unopened', () {
      fakeAsync((clock) {
        final lease = _ProtectionLease(refuse: true);
        var factoryCalls = 0;
        final owner = CallScopedMediaBundleOwner(
          protection: lease,
          createBundle: (callId) {
            factoryCalls++;
            return _BundleHarness(callId).value;
          },
        );
        Object? failure;
        unawaited(
          owner.execute(negotiate, _snapshot(_firstCallId)).catchError((
            Object error,
          ) {
            failure = error;
            return null;
          }),
        );
        clock.flushMicrotasks();
        expect(lease.log, <String>['acquire:refused']);
        expect(
          factoryCalls,
          0,
          reason: 'native media needs a confirmed protection owner',
        );

        // The broker keeps refusing: the owner asks again at its interval,
        // still without media.
        clock.elapse(owner.protectionRetryInterval);
        expect(lease.log, <String>['acquire:refused', 'acquire:refused']);
        expect(factoryCalls, 0);
        expect(failure, isNull);

        // The coordinator's media-preparation budget ends the call and its
        // cleanup retires the pending call here, which stops the asking.
        unawaited(owner.closeCall(_firstCallId));
        clock.elapse(owner.protectionRetryInterval);
        expect(
          failure,
          _ownerFailure(CallScopedMediaBundleOwnerErrorCode.retiredCall),
        );
        expect(lease.log, <String>['acquire:refused', 'acquire:refused']);
        expect(factoryCalls, 0);

        unawaited(owner.close());
        clock.flushMicrotasks();
      });
    });

    test(
      'a restart in progress delays the media factory until the broker grants',
      () async {
        final lease = _ProtectionLease()..refusalsLeft = 2;
        late final _BundleHarness bundle;
        final owner = CallScopedMediaBundleOwner(
          protection: lease,
          protectionRetryInterval: Duration.zero,
          createBundle: (callId) {
            lease.log.add('factory');
            bundle = _BundleHarness(callId);
            return bundle.value;
          },
        );
        addTearDown(owner.close);

        await owner.execute(negotiate, _snapshot(_firstCallId));
        expect(lease.log, <String>[
          'acquire:refused',
          'acquire:refused',
          'acquire:1',
          'factory',
        ]);
        expect(lease.heldGeneration, 1);
        expect(bundle.executor.effects, <CallEffectType>[
          CallEffectType.startNegotiation,
        ]);

        await owner.closeCall(_firstCallId);
        expect(lease.log.last, 'release:1');
        expect(lease.holder, isNull);
      },
    );

    test('a grant that lands after the call was closed goes back and opens '
        'no media', () async {
      final lease = _ProtectionLease()..gate = Completer<void>();
      final answer = lease.gate!;
      var factoryCalls = 0;
      final owner = CallScopedMediaBundleOwner(
        protection: lease,
        createBundle: (callId) {
          factoryCalls++;
          return _BundleHarness(callId).value;
        },
      );
      addTearDown(owner.close);

      final execution = owner.execute(negotiate, _snapshot(_firstCallId));
      await Future<void>.delayed(Duration.zero);
      final closing = owner.closeCall(_firstCallId);
      answer.complete();

      await expectLater(
        execution,
        throwsA(_ownerFailure(CallScopedMediaBundleOwnerErrorCode.retiredCall)),
      );
      await closing;
      expect(factoryCalls, 0);
      expect(lease.log, <String>['acquire:1', 'release:1']);
      expect(lease.holder, isNull);
    });

    test(
      'a missing broker opens media unprotected and never releases',
      () async {
        final lease = _ProtectionLease(unavailable: true);
        late final _BundleHarness bundle;
        final owner = CallScopedMediaBundleOwner(
          protection: lease,
          createBundle: (callId) async {
            bundle = _BundleHarness(callId);
            return bundle.value;
          },
        );
        addTearDown(owner.close);

        await owner.execute(negotiate, _snapshot(_firstCallId));
        expect(bundle.executor.effects, <CallEffectType>[
          CallEffectType.startNegotiation,
        ]);

        await owner.closeCall(_firstCallId);
        expect(bundle.closeCalls, 1);
        expect(lease.log, <String>['acquire:unavailable']);
      },
    );

    test('a failed media close keeps its protection until a retry confirms the '
        'cleanup', () async {
      final lease = _ProtectionLease();
      var closeAttempts = 0;
      final owner = CallScopedMediaBundleOwner(
        protection: lease,
        createBundle: (callId) {
          final harness = _BundleHarness(callId);
          return CallScopedMediaBundle(
            callId: callId,
            engine: harness.engine,
            audioController: harness.audioController,
            negotiationExecutor: harness.executor,
            close: () async {
              if (++closeAttempts == 1) {
                throw StateError('native media cleanup not confirmed');
              }
              await harness.audioController.close();
            },
          );
        },
      );
      addTearDown(owner.close);

      await owner.execute(negotiate, _snapshot(_firstCallId));
      await expectLater(owner.closeCall(_firstCallId), throwsStateError);
      expect(lease.log, <String>['acquire:1']);
      expect(
        lease.heldGeneration,
        1,
        reason:
            'the media bundle failed before any native teardown '
            'confirmation',
      );

      await owner.closeCall(_firstCallId);
      expect(closeAttempts, 2);
      expect(lease.log, <String>['acquire:1', 'release:1']);
      expect(lease.holder, isNull);
    });

    test('a late-created bundle whose cleanup fails keeps its protection until '
        'the retry', () async {
      final lease = _ProtectionLease();
      final creationGate = Completer<void>();
      late final _BundleHarness bundle;
      final owner = CallScopedMediaBundleOwner(
        protection: lease,
        createBundle: (callId) async {
          await creationGate.future;
          bundle = _BundleHarness(
            callId,
            onCloseAttempt: (attempt) async {
              if (attempt == 1) throw StateError('close failed');
            },
          );
          return bundle.value;
        },
      );
      addTearDown(owner.close);

      final execution = owner.execute(negotiate, _snapshot(_firstCallId));
      await Future<void>.delayed(Duration.zero);
      final closing = owner.closeCall(_firstCallId);
      creationGate.complete();

      await expectLater(
        execution,
        throwsA(
          _ownerFailure(CallScopedMediaBundleOwnerErrorCode.cleanupFailed),
        ),
      );
      await expectLater(
        closing,
        throwsA(
          _ownerFailure(CallScopedMediaBundleOwnerErrorCode.cleanupFailed),
        ),
      );
      expect(lease.log, <String>['acquire:1']);
      expect(lease.heldGeneration, 1);

      await owner.closeCall(_firstCallId);
      expect(bundle.closeCalls, 2);
      expect(lease.log, <String>['acquire:1', 'release:1']);
      expect(lease.holder, isNull);
    });

    test(
      'an unconfirmed cleanup keeps its grant past the tombstone bound',
      () async {
        final lease = _ProtectionLease();
        var allowClose = false;
        var nativeClosed = false;
        final owner = CallScopedMediaBundleOwner(
          protection: lease,
          protectionRetryInterval: const Duration(milliseconds: 10),
          retiredCallCapacity: 1,
          createBundle: (callId) {
            final harness = _BundleHarness(callId);
            if (callId != _firstCallId) return harness.value;
            return CallScopedMediaBundle(
              callId: callId,
              engine: harness.engine,
              audioController: harness.audioController,
              negotiationExecutor: harness.executor,
              close: () async {
                if (!allowClose) {
                  throw StateError('native cleanup not confirmed');
                }
                await harness.audioController.close();
                nativeClosed = true;
              },
            );
          },
        );
        addTearDown(owner.close);

        await owner.execute(negotiate, _snapshot(_firstCallId));
        await expectLater(owner.closeCall(_firstCallId), throwsStateError);

        // Retiring the waiting call goes past the tombstone bound. That is not
        // native teardown, so the first call keeps its grant.
        final second = owner.execute(negotiate, _snapshot(_secondCallId));
        final secondRetired = expectLater(
          second,
          throwsA(isA<CallScopedMediaBundleOwnerException>()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));
        await owner.closeCall(_secondCallId);
        await secondRetired;
        expect(nativeClosed, isFalse);
        expect(lease.log, <String>['acquire:1']);
        expect(lease.heldGeneration, 1);

        allowClose = true;
        await owner.closeCall(_firstCallId);
        expect(nativeClosed, isTrue);
        expect(lease.log, <String>['acquire:1', 'release:1']);
        expect(lease.holder, isNull);
      },
    );
  });

  // The one fail-open case, pinned against its justification: Dart and the
  // Go binary ship in one app build, so the native method can only be missing
  // in a mismatched build (an iOS xcframework or an AAR older than this Dart).
  // A broker that exists and refuses is the opposite case and opens nothing.
  group('protection capability', () {
    const negotiate = CallEffect(CallEffectType.startNegotiation);
    late List<Map<String, dynamic>> flowEvents;

    setUp(() {
      flowEventLoggingEnabled = false;
      BridgeCallMediaProtectionLease.resetGenerations();
      flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(
        (payload) => flowEvents.add(Map<String, dynamic>.from(payload)),
      );
    });

    tearDown(() {
      debugSetFlowEventSink(null);
      flowEventLoggingEnabled = true;
    });

    List<Map<String, dynamic>> protectionEvents() => <Map<String, dynamic>>[
      for (final event in flowEvents)
        if (event['event'] == 'CALL_MEDIA_PROTECTION')
          Map<String, dynamic>.from(event['details'] as Map),
    ];

    test('a missing native method opens media once and records one bounded '
        'diagnostic', () async {
      // What GoBridgeClient answers when the native binary has no
      // callMediaProtection method.
      final bridge = _AnsweringBridge(
        (_) => <String, Object?>{'ok': false, 'errorCode': 'MISSING_PLUGIN'},
      );
      var factoryCalls = 0;
      late final _BundleHarness bundle;
      final owner = CallScopedMediaBundleOwner(
        protection: BridgeCallMediaProtectionLease(bridge: bridge),
        createBundle: (callId) {
          factoryCalls++;
          bundle = _BundleHarness(callId);
          return bundle.value;
        },
      );
      addTearDown(owner.close);

      await owner.execute(negotiate, _snapshot(_firstCallId));
      await owner.execute(
        const CallEffect(CallEffectType.deliverAnswer),
        _snapshot(_firstCallId),
      );
      expect(factoryCalls, 1);
      expect(bundle.executor.effects, <CallEffectType>[
        CallEffectType.startNegotiation,
        CallEffectType.deliverAnswer,
      ]);
      expect(bridge.payloads, <Map<String, Object?>>[
        {'held': true, 'generation': 1},
      ]);
      expect(protectionEvents(), <Map<String, Object?>>[
        {'action': 'acquire', 'outcome': 'unavailable', 'generation': 1},
      ]);

      await owner.closeCall(_firstCallId);
      expect(bundle.closeCalls, 1);
      expect(
        bridge.payloads,
        hasLength(1),
        reason: 'nothing was granted, so nothing is handed back',
      );
      expect(protectionEvents(), hasLength(1));
    });

    test('a present broker that keeps refusing never opens media before the '
        'budget ends', () {
      fakeAsync((clock) {
        final bridge = _AnsweringBridge(
          (payload) => <String, Object?>{
            'ok': true,
            'held': false,
            'generation': payload['generation'],
            'reason': 'restart_in_progress',
          },
        );
        var factoryCalls = 0;
        final owner = CallScopedMediaBundleOwner(
          protection: BridgeCallMediaProtectionLease(bridge: bridge),
          createBundle: (callId) {
            factoryCalls++;
            return _BundleHarness(callId).value;
          },
        );
        Object? failure;
        unawaited(
          owner.execute(negotiate, _snapshot(_firstCallId)).catchError((
            Object error,
          ) {
            failure = error;
            return null;
          }),
        );

        // The coordinator bounds media preparation at 45 s. Until then the
        // owner keeps asking and opens nothing.
        clock.elapse(const Duration(seconds: 45));
        expect(factoryCalls, 0);
        expect(failure, isNull);
        expect(
          bridge.payloads,
          hasLength(181),
          reason: 'one ask at once, then one every 250 ms',
        );
        expect(
          bridge.payloads.map((payload) => payload['held']).toSet(),
          <Object?>{true},
        );
        expect(
          protectionEvents().map((event) => event['outcome']).toSet(),
          <Object?>{'refused'},
        );

        // The budget ended: the call's cleanup retires the pending call.
        unawaited(owner.closeCall(_firstCallId));
        clock.elapse(owner.protectionRetryInterval);
        expect(
          failure,
          _ownerFailure(CallScopedMediaBundleOwnerErrorCode.retiredCall),
        );
        expect(factoryCalls, 0);
        expect(
          bridge.payloads,
          hasLength(181),
          reason: 'no grant arrived, so there is nothing to hand back',
        );

        unawaited(owner.close());
        clock.flushMicrotasks();
      });
    });
  });
}

/// Answers every `call_media:protection` request through [answer].
final class _AnsweringBridge extends Bridge {
  _AnsweringBridge(this.answer);

  final Map<String, Object?> Function(Map<String, dynamic> payload) answer;
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  @override
  bool get isInitialized => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> reinitialize() async {}

  @override
  void dispose() {}

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    expect(request['cmd'], 'call_media:protection');
    final payload = Map<String, Object?>.from(request['payload'] as Map);
    payloads.add(payload);
    return jsonEncode(answer(request['payload'] as Map<String, dynamic>));
  }
}

/// Models the Go broker as the owner sees it: a grant, a refusal word, or no
/// broker at all, with a holder that only the exact grant clears.
final class _ProtectionLease implements CallMediaProtectionLease {
  _ProtectionLease({this.refuse = false, this.unavailable = false});

  final bool refuse;
  final bool unavailable;
  final List<String> log = <String>[];
  CallMediaProtectionGrant? holder;

  /// The next acquire waits for this before answering (a broker answering
  /// after the caller moved on).
  Completer<void>? gate;

  /// Refusals left before the broker grants (a restart in progress).
  int refusalsLeft = 0;
  int _generations = 0;

  int? get heldGeneration => holder?.generation;

  @override
  Future<CallMediaProtectionAdmission> acquire() async {
    final pending = gate;
    if (pending != null) {
      gate = null;
      await pending.future;
    }
    if (unavailable) {
      log.add('acquire:unavailable');
      return const CallMediaProtectionUnavailable();
    }
    if (refuse || refusalsLeft > 0) {
      if (refusalsLeft > 0) refusalsLeft--;
      log.add('acquire:refused');
      return const CallMediaProtectionRefused('restart_in_progress');
    }
    final grant = CallMediaProtectionGrant(
      generation: ++_generations,
      incarnation: 1,
    );
    holder = grant;
    log.add('acquire:${grant.generation}');
    return CallMediaProtectionGranted(grant);
  }

  @override
  Future<void> release(CallMediaProtectionGrant grant) async {
    log.add('release:${grant.generation}');
    if (holder == grant) holder = null;
  }
}

final class _BundleHarness {
  _BundleHarness(this.callId, {this.failClose = false, this.onCloseAttempt}) {
    audioController = CallAudioController(
      engine: engine,
      microphonePermission: const _Permission(),
      mediaConflicts: const _MediaConflicts(),
      audioSession: const _AudioSession(),
    );
    value = CallScopedMediaBundle(
      callId: callId,
      engine: engine,
      audioController: audioController,
      negotiationExecutor: executor,
      close: () async {
        closeCalls++;
        await audioController.close();
        await onCloseAttempt?.call(closeCalls);
        if (failClose) throw StateError('close failed');
      },
    );
  }

  final CallId callId;
  final bool failClose;
  final Future<void> Function(int attempt)? onCloseAttempt;
  final _Engine engine = _Engine();
  final _RecordingExecutor executor = _RecordingExecutor();
  late final CallAudioController audioController;
  late final CallScopedMediaBundle value;
  int closeCalls = 0;
}

final class _RecordingExecutor implements CallEffectExecutor {
  final List<CallEffectType> effects = <CallEffectType>[];

  @override
  Future<CallEvent?> execute(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) async {
    effects.add(effect.type);
    return null;
  }
}

final class _Permission implements CallMicrophonePermission {
  const _Permission();

  @override
  Future<MicPermissionStatus> request() async => MicPermissionStatus.granted;
}

final class _Lease implements CallMediaConflictLease {
  const _Lease();

  @override
  Future<void> release() async {}
}

final class _MediaConflicts implements CallMediaConflictPort {
  const _MediaConflicts();

  @override
  Future<CallMediaConflictLease> acquireForCall() async => const _Lease();
}

final class _AudioSession implements CallForegroundAudioSession {
  const _AudioSession();

  @override
  Stream<CallAudioSessionInterruption> get interruptions =>
      const Stream<CallAudioSessionInterruption>.empty();

  @override
  bool get ownsSession => false;

  @override
  Future<void> activate() async {}

  @override
  Future<void> deactivate() async {}
}

final class _Engine implements CallEngine {
  var closeCalls = 0;

  @override
  Stream<CallEngineEvent> get events => const Stream<CallEngineEvent>.empty();

  @override
  Stream<CallIceCandidate> get localCandidates =>
      const Stream<CallIceCandidate>.empty();

  @override
  List<CallEngineEvent> get recentEvents => const <CallEngineEvent>[];

  @override
  bool get isClosed => closeCalls > 0;

  @override
  int get candidateBatchCapacity => 8;

  @override
  int get iceGeneration => 0;

  @override
  Future<void> createConnection(
    CallConnectionConfiguration configuration,
  ) async {}

  @override
  Future<CallSessionDescription> createOffer() => throw UnimplementedError();

  @override
  Future<CallSessionDescription> createAnswer() => throw UnimplementedError();

  @override
  Future<void> setLocalDescription(CallSessionDescription description) async {}

  @override
  Future<void> setRemoteDescription(CallSessionDescription description) async {}

  @override
  Future<void> addIceCandidates(List<CallIceCandidate> candidates) async {}

  @override
  Future<int> restartIce({List<CallIceServer> iceServers = const []}) async =>
      1;

  @override
  Future<void> setLocalAudioEnabled(bool enabled) async {}

  @override
  Future<void> setAudioSessionActive(bool active) async {}

  @override
  Future<List<CallAudioOutputRoute>> supportedOutputRoutes() async =>
      const <CallAudioOutputRoute>[CallAudioOutputRoute.systemDefault];

  @override
  Future<void> selectOutputRoute(CallAudioOutputRoute route) async {}

  @override
  Future<CallConnectionSnapshot> snapshot() async =>
      const CallConnectionSnapshot(
        state: CallConnectionState.newConnection,
        transportPolicy: CallTransportPolicy.relayOnly,
        transport: CallTransportClass.unknown,
        quality: CallQualityBand.unknown,
        localAudioCaptureTrackCount: 0,
        localVideoCaptureTrackCount: 0,
        audioReceiveTransceiverCount: 0,
        videoTransceiverCount: 0,
      );

  @override
  Future<void> close() async {
    closeCalls++;
  }
}
