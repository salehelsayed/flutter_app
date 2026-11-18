import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_app/features/call/application/call_recovery_budget.dart';
import 'package:flutter_app/features/call/infrastructure/call_endpoint_recovery.dart';
import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/call/domain/received_call_wake_handle_store.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_app/features/call/infrastructure/call_trusted_roster_provider.dart';
import 'package:flutter_app/features/call/infrastructure/production_call_endpoint_resolution.dart';
import 'package:flutter_test/flutter_test.dart';

const _now = 2000000;
const _account = 'remote-account';
const _device = 'remote-device';

void main() {
  test('BL26-HA six authorizations share three remote lookups', () {
    fakeAsync((async) {
      final rig = _RecoveryRig(async);
      var completed = 0;
      Future<void> resolveAll() async {
        for (var i = 0; i < 6; i++) {
          await rig.resolve();
          completed++;
        }
      }

      unawaited(resolveAll());
      async.flushMicrotasks();
      expect(completed, 6);
      expect(rig.authority.lookups, 3);
      expect(rig.roster.loads, greaterThanOrEqualTo(6));
      expect(rig.wake.reads, greaterThanOrEqualTo(6));
    });
  });

  test(
    'BL26-HA newer same-authority revision survives cache quota and original deadline',
    () {
      fakeAsync((async) {
        final rig = _RecoveryRig(async);
        rig.authority.preferenceEpoch = 2;
        final revisions = <int>[];
        Object? failure;
        var completed = false;
        Future<void> exercise() async {
          try {
            revisions.add((await rig.resolve()).preferenceEpoch);
            rig.authority.preferenceEpoch = 3;
            for (var i = 0; i < 5; i++) {
              revisions.add((await rig.resolve()).preferenceEpoch);
            }
          } catch (error) {
            failure = error;
          } finally {
            completed = true;
          }
        }

        unawaited(exercise());
        async.flushMicrotasks();
        expect(completed, isTrue);
        expect(failure, isNull);
        expect(revisions, [2, 3, 3, 3, 3, 3]);
        expect(rig.authority.lookups, 3);

        async.elapse(const Duration(seconds: 14));
        ResolvedCallEndpoint? cached;
        completed = false;
        rig.resolve().then<void>(
          (endpoint) {
            cached = endpoint;
            completed = true;
          },
          onError: (Object error) {
            failure = error;
            completed = true;
          },
        );
        async.flushMicrotasks();
        expect(completed, isTrue);
        expect(failure, isNull);
        expect(cached?.preferenceEpoch, 3);
        expect(rig.authority.lookups, 3);

        async.elapse(const Duration(seconds: 1));
        var deadlineSucceeded = false;
        completed = false;
        rig.resolve().then<void>(
          (_) {
            deadlineSucceeded = true;
            completed = true;
          },
          onError: (Object error) {
            failure = error;
            completed = true;
          },
        );
        async.flushMicrotasks();
        expect(completed, isTrue);
        expect(deadlineSucceeded, isFalse);
        expect(failure, isA<CallEndpointRecoveryUnavailable>());
        expect(rig.authority.lookups, 3);
      });
    },
  );

  test('BL26-HA revision rollback after renewal destroys episode authority', () {
    fakeAsync((async) {
      final rig = _RecoveryRig(async);
      rig.authority.preferenceEpoch = 3;
      ResolvedCallEndpoint? renewed;
      Object? renewalFailure;
      var completed = false;
      rig.resolve().then<void>(
        (endpoint) {
          renewed = endpoint;
          completed = true;
        },
        onError: (Object error) {
          renewalFailure = error;
          completed = true;
        },
      );
      async.flushMicrotasks();
      expect(completed, isTrue);
      expect(renewalFailure, isNull);
      expect(renewed?.preferenceEpoch, 3);
      expect(rig.authority.lookups, 1);

      final failures = <Object>[];
      var successes = 0;
      completed = false;
      Future<void> rejectRollbackAndRevival() async {
        for (final revision in [2, 3]) {
          rig.authority.preferenceEpoch = revision;
          try {
            await rig.resolve();
            successes++;
          } catch (error) {
            failures.add(error);
          }
        }
        completed = true;
      }

      unawaited(rejectRollbackAndRevival());
      async.flushMicrotasks();
      expect(completed, isTrue);
      expect(successes, 0);
      expect(failures, hasLength(2));
      expect(
        failures,
        everyElement(
          isA<CallEndpointResolutionException>().having(
            (error) => error.code,
            'code',
            CallEndpointResolutionCode.mismatched,
          ),
        ),
      );
      expect(rig.authority.lookups, 2);
    });
  });

  test('BL26-HA revision below admission is refused', () {
    fakeAsync((async) {
      final rig = _RecoveryRig(async);
      rig.authority.preferenceEpoch = 0;
      Object? failure;
      var completed = false;
      var succeeded = false;
      rig.resolve().then<void>(
        (_) {
          succeeded = true;
          completed = true;
        },
        onError: (Object error) {
          failure = error;
          completed = true;
        },
      );
      async.flushMicrotasks();
      expect(completed, isTrue);
      expect(succeeded, isFalse);
      expect(
        failure,
        isA<CallEndpointResolutionException>().having(
          (error) => error.code,
          'code',
          CallEndpointResolutionCode.mismatched,
        ),
      );
      expect(rig.authority.lookups, 1);
    });
  });

  test('BL26-HA absent endpoint cannot erase accepted revision floor', () {
    fakeAsync((async) {
      final rig = _RecoveryRig(async);
      rig.authority.preferenceEpoch = 2;
      ResolvedCallEndpoint? renewed;
      Object? renewalFailure;
      final refusals = <Object>[];
      var unexpectedSuccesses = 0;
      var completed = false;
      Future<void> exercise() async {
        try {
          renewed = await rig.resolve();
          rig.authority.response = () async => null;
          try {
            await rig.resolve();
            unexpectedSuccesses++;
          } catch (error) {
            refusals.add(error);
          }
          rig.authority.response = null;
          rig.authority.preferenceEpoch = 1;
          try {
            await rig.resolve();
            unexpectedSuccesses++;
          } catch (error) {
            refusals.add(error);
          }
        } catch (error) {
          renewalFailure = error;
        } finally {
          completed = true;
        }
      }

      unawaited(exercise());
      async.flushMicrotasks();
      expect(completed, isTrue);
      expect(renewalFailure, isNull);
      expect(renewed?.preferenceEpoch, 2);
      expect(unexpectedSuccesses, 0);
      expect(refusals, hasLength(2));
      expect(refusals.first, isA<CallEndpointRecoveryUnavailable>());
      expect(
        refusals.last,
        isA<CallEndpointResolutionException>().having(
          (error) => error.code,
          'code',
          CallEndpointResolutionCode.mismatched,
        ),
      );
      expect(rig.authority.lookups, 3);
    });
  });

  for (final fallback in ['transport', 'timeout']) {
    test('BL26-HA absent endpoint cannot roll back via $fallback or quota', () {
      fakeAsync((async) {
        final rig = _RecoveryRig(async);
        rig.authority.preferenceEpoch = 2;
        final held = Completer<SignedCallEndpointRecord?>();
        ResolvedCallEndpoint? renewed;
        Object? renewalFailure;
        final refusals = <Object>[];
        var unexpectedSuccesses = 0;
        var completed = false;
        Future<void> exercise() async {
          try {
            renewed = await rig.resolve();
            rig.authority.response = () async => null;
            try {
              await rig.resolve();
              unexpectedSuccesses++;
            } catch (error) {
              refusals.add(error);
            }
            rig.authority.response = fallback == 'timeout'
                ? () => held.future
                : () async => throw const CallAuthorityException(
                    CallAuthorityErrorCode.bridgeFailure,
                    isTransient: true,
                  );
            for (var i = 0; i < 2; i++) {
              try {
                await rig.resolve();
                unexpectedSuccesses++;
              } catch (error) {
                refusals.add(error);
              }
            }
          } catch (error) {
            renewalFailure = error;
          } finally {
            completed = true;
          }
        }

        unawaited(exercise());
        async.flushMicrotasks();
        expect(renewalFailure, isNull);
        expect(renewed?.preferenceEpoch, 2);
        if (fallback == 'timeout') {
          expect(completed, isFalse);
          async.elapse(const Duration(seconds: 2));
        }
        async.flushMicrotasks();
        expect(completed, isTrue);
        expect(unexpectedSuccesses, 0);
        expect(refusals, hasLength(3));
        expect(refusals, everyElement(isA<CallEndpointRecoveryUnavailable>()));
        expect(rig.authority.lookups, 3);
        held.complete(null);
        async.flushMicrotasks();
        expect(unexpectedSuccesses, 0);
        expect(rig.authority.lookups, 3);
      });
    });
  }

  for (final changed in ['routing', 'platform', 'capabilities']) {
    test('BL26-HA newer revision still rejects changed $changed', () {
      fakeAsync((async) {
        final rig = _RecoveryRig(async);
        rig.authority.preferenceEpoch = 2;
        switch (changed) {
          case 'routing':
            rig.authority.routingHandle = '1123456789abcdef0123456789abcdef';
            break;
          case 'platform':
            rig.authority.platform = CallEndpointPlatform.ios;
            break;
          case 'capabilities':
            rig.authority.capabilities = const {'voice_call_v1'};
            break;
        }
        Object? failure;
        var completed = false;
        var succeeded = false;
        rig.resolve().then<void>(
          (_) {
            succeeded = true;
            completed = true;
          },
          onError: (Object error) {
            failure = error;
            completed = true;
          },
        );
        async.flushMicrotasks();
        expect(completed, isTrue);
        expect(succeeded, isFalse);
        expect(
          failure,
          isA<CallEndpointResolutionException>().having(
            (error) => error.code,
            'code',
            CallEndpointResolutionCode.mismatched,
          ),
        );
        expect(rig.authority.lookups, 1);
      });
    });
  }

  for (final denial in [
    'blocked',
    'not-accepted',
    'unlinked',
    'no-device',
    'expired-wake',
    'wrong-wake-device',
    'wrong-wake-epoch',
    'rotated-key',
    'relationship',
  ]) {
    test('BL26-HA episode cache still rejects fresh local $denial', () {
      fakeAsync((async) {
        final rig = _RecoveryRig(async);
        Object? failure;
        Future<void> exercise() async {
          for (var i = 0; i < 3; i++) {
            await rig.resolve();
          }
          rig.roster.denial = denial;
          rig.wake.denial = denial;
          try {
            await rig.resolve();
          } catch (error) {
            failure = error;
          }
        }

        unawaited(exercise());
        async.flushMicrotasks();
        expect(failure, isA<CallEndpointResolutionException>());
        expect(rig.authority.lookups, 3);
      });
    });
  }

  test(
    'BL26-HA typed transient pin permission shares the three-lookup ceiling',
    () {
      fakeAsync((async) {
        final rig = _RecoveryRig(async);
        rig.authority.response = () async => throw const CallAuthorityException(
          CallAuthorityErrorCode.bridgeFailure,
          isTransient: true,
        );
        var completed = 0;
        Future<void> exercise() async {
          for (var i = 0; i < 6; i++) {
            await rig.resolve();
            completed++;
          }
        }

        unawaited(exercise());
        async.flushMicrotasks();
        expect(completed, 6);
        expect(rig.authority.lookups, 3);
        expect(rig.roster.loads, greaterThanOrEqualTo(6));
      });
    },
  );

  test('BL26-HA untyped bridge failure cannot authorize the admitted pin', () {
    fakeAsync((async) {
      final rig = _RecoveryRig(async);
      rig.authority.response = () async => throw const CallAuthorityException(
        CallAuthorityErrorCode.bridgeFailure,
      );
      Object? failure;
      rig.resolve().catchError((Object error) {
        failure = error;
        return rig.admitted;
      });
      async.flushMicrotasks();
      expect(failure, isA<CallEndpointResolutionException>());
      expect(rig.authority.lookups, 1);
    });
  });

  test('BL26-HA verified cache cannot outlive the canonical deadline', () {
    fakeAsync((async) {
      final rig = _RecoveryRig(async);
      var prepared = false;
      Future<void> fill() async {
        for (var i = 0; i < 3; i++) {
          await rig.resolve();
        }
        prepared = true;
      }

      unawaited(fill());
      async.flushMicrotasks();
      expect(prepared, isTrue);
      async.elapse(const Duration(seconds: 15));
      Object? failure;
      rig.resolve().catchError((Object error) {
        failure = error;
        return rig.admitted;
      });
      async.flushMicrotasks();
      expect(failure, isA<CallEndpointRecoveryUnavailable>());
      expect(rig.authority.lookups, 3);
    });
  });

  test('BL26-HA changed signaling binding revokes verified cache', () {
    fakeAsync((async) {
      final rig = _RecoveryRig(async);
      Object? failure;
      Future<void> exercise() async {
        for (var i = 0; i < 3; i++) {
          await rig.resolve();
        }
        rig.bindingCurrent = false;
        try {
          await rig.resolve();
        } catch (error) {
          failure = error;
        }
      }

      unawaited(exercise());
      async.flushMicrotasks();
      expect(failure, isA<CallEndpointResolutionException>());
      expect(rig.authority.lookups, 3);
    });
  });

  test('BL26-HA denial after success destroys episode cache', () {
    fakeAsync((async) {
      final rig = _RecoveryRig(async);
      final failures = <Object>[];
      Future<void> exercise() async {
        await rig.resolve();
        rig.authority.response = () async => throw const CallAuthorityException(
          CallAuthorityErrorCode.bridgeFailure,
          relayErrorCode: 'CALL_UNAUTHORIZED',
        );
        for (var i = 0; i < 2; i++) {
          try {
            await rig.resolve();
          } catch (error) {
            failures.add(error);
          }
        }
      }

      unawaited(exercise());
      async.flushMicrotasks();
      expect(failures, hasLength(2));
      expect(failures, everyElement(isA<CallEndpointResolutionException>()));
      expect(rig.authority.lookups, 2);
    });
  });

  test(
    'BL26-HA lookup slice is exactly two seconds and late result cannot revive ownership',
    () {
      fakeAsync((async) {
        final rig = _RecoveryRig(async);
        final held = Completer<SignedCallEndpointRecord?>();
        rig.authority.response = () => held.future;
        ResolvedCallEndpoint? result;
        rig.resolve().then((value) => result = value);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1999));
        expect(result, isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(result, isNotNull);
        expect(rig.authority.lookups, 1);
        rig.current = false;
        held.complete(null);
        async.flushMicrotasks();
        Object? failure;
        rig.resolve().catchError((Object error) {
          failure = error;
          return rig.admitted;
        });
        async.flushMicrotasks();
        expect(failure, isA<CallEndpointRecoveryUnavailable>());
        expect(rig.authority.lookups, 1);
      });
    },
  );

  test('BL26-HA lookup slice clamps to original remaining half second', () {
    fakeAsync((async) {
      final rig = _RecoveryRig(async);
      final held = Completer<SignedCallEndpointRecord?>();
      rig.authority.response = () => held.future;
      async.elapse(const Duration(milliseconds: 14500));
      Object? failure;
      var success = false;
      rig.resolve().then<void>(
        (_) {
          success = true;
        },
        onError: (Object error) {
          failure = error;
        },
      );
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 499));
      expect(failure, isNull);
      expect(success, isFalse);
      async.elapse(const Duration(milliseconds: 1));
      expect(failure, isA<CallEndpointRecoveryUnavailable>());
      expect(success, isFalse);
      held.complete(null);
      async.flushMicrotasks();
      expect(success, isFalse);
      expect(rig.authority.lookups, 1);
    });
  });

  test(
    'BL26-HA a new episode starts with no verified cache or transient pin permission',
    () {
      fakeAsync((async) {
        final rig = _RecoveryRig(async);
        Object? failure;
        Future<void> exercise() async {
          for (var i = 0; i < 4; i++) {
            await rig.resolve();
          }
          final old = rig.recovery;
          rig.recovery = CallEndpointRecovery(
            budget: rig.newBudget(),
            admitted: rig.admitted,
          );
          Object? staleFailure;
          try {
            await rig.resolve(episode: old);
          } catch (error) {
            staleFailure = error;
          }
          expect(staleFailure, isA<CallEndpointRecoveryUnavailable>());
          expect(rig.authority.lookups, 3);
          rig.authority.response = () async => null;
          try {
            await rig.resolve();
          } catch (error) {
            failure = error;
          }
        }

        unawaited(exercise());
        async.flushMicrotasks();
        expect(failure, isA<CallEndpointRecoveryUnavailable>());
        expect(rig.authority.lookups, 4);
      });
    },
  );

  for (final denial in [
    'not-accepted',
    'blocked',
    'no-device',
    'unlinked',
    'expired-wake',
    'wrong-wake-device',
    'wrong-wake-epoch',
  ]) {
    test('BL26-HA local $denial refuses before remote lookup', () async {
      final authority = _Authority();
      final roster = _Roster(denial);
      final wake = _WakeStore(denial);
      Object? failure;
      try {
        await resolveProductionCallEndpoint(
          contactAccountPeerId: _account,
          resolver: CallEndpointResolver(
            nowMs: () => _now,
            verifyEndpointSignature: (_, _) async => true,
          ),
          rosterProvider: roster,
          authorityClient: authority,
          receivedCallWakeHandleStore: wake,
        );
      } catch (error) {
        failure = error;
      }
      expect(failure, isA<CallEndpointResolutionException>());
      expect(
        authority.lookups,
        0,
        reason:
            'Local authority denial must precede any remote wait or fallback',
      );
    });
  }

  test(
    'BL26-HA valid local authority retains signed endpoint resolution',
    () async {
      final authority = _Authority();
      final endpoint = await resolveProductionCallEndpoint(
        contactAccountPeerId: _account,
        resolver: CallEndpointResolver(
          nowMs: () => _now,
          verifyEndpointSignature: (_, key) async => key == 'signing-key',
        ),
        rosterProvider: _Roster('valid'),
        authorityClient: authority,
        receivedCallWakeHandleStore: _WakeStore('valid'),
      );
      expect(authority.lookups, 1);
      expect(endpoint.accountPeerId, _account);
      expect(endpoint.devicePeerId, _device);
      expect(endpoint.deviceKeyEpoch, 1);
      expect(endpoint.capabilities, {'voice_call_v1', 'video_call_v2'});
    },
  );
}

final class _Roster implements CallTrustedRosterProvider {
  _Roster(this.denial);
  String denial;

  int loads = 0;
  @override
  Future<CallTrustedRosterSnapshot> loadForContact(String account) async {
    loads++;
    return CallTrustedRosterSnapshot(
      contactAccountPeerId: account,
      contactAccepted: denial != 'not-accepted',
      contactBlocked: denial == 'blocked',
      devices: denial == 'no-device'
          ? []
          : [
              TrustedCallDeviceAuthority(
                accountPeerId: _account,
                devicePeerId: _device,
                linked: denial != 'unlinked',
                deviceKeyEpoch: 1,
                signingPublicKey: denial == 'rotated-key'
                    ? 'changed-key'
                    : 'signing-key',
                mlKemPublicKey: 'kem-key',
                admissionAuthority: (
                  fingerprint: 'friend',
                  relationshipRevision: denial == 'relationship' ? 2 : 1,
                ),
              ),
            ],
    );
  }

  @override
  Future<TrustedCallDeviceAuthority?> resolveAuthenticatedTransport(
    String peer,
  ) async => null;
}

final class _WakeStore implements ReceivedCallWakeHandleStore {
  _WakeStore(this.denial);
  String denial;

  int reads = 0;
  @override
  Future<CallWakeHandleGrant?> readForIssuer(String account) async {
    reads++;
    return CallWakeHandleGrant(
      handle: 'fedcba9876543210fedcba9876543210',
      recipientDevicePeerId: denial == 'wrong-wake-device'
          ? 'other-device'
          : _device,
      deviceKeyEpoch: denial == 'wrong-wake-epoch' ? 2 : 1,
      generation: 1,
      issuedAtMs: _now - 1000,
      expiresAtMs: denial == 'expired-wake' ? _now - 1 : _now + 60000,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Authority implements CallAuthorityClient {
  int lookups = 0;
  int preferenceEpoch = 1;
  String routingHandle = '0123456789abcdef0123456789abcdef';
  CallEndpointPlatform platform = CallEndpointPlatform.android;
  Set<String> capabilities = const {'voice_call_v1', 'video_call_v2'};
  Future<SignedCallEndpointRecord?> Function()? response;

  @override
  Future<SignedCallEndpointRecord?> getEndpoint(String account) async {
    lookups++;
    if (response != null) return response!();
    final record = CallEndpointRecord(
      accountPeerId: account,
      devicePeerId: _device,
      capabilities: capabilities,
      platform: platform,
      expiresAtMs: _now + 60000,
      preferenceEpoch: preferenceEpoch,
      deviceKeyEpoch: 1,
      routingHandle: routingHandle,
    );
    return SignedCallEndpointRecord(
      record: record,
      signature: 'c2ln',
      canonicalRecordBase64: 'e30=',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RecoveryRig {
  _RecoveryRig(this.async) {
    resolver = CallEndpointResolver(
      nowMs: () => _now + async.elapsed.inMilliseconds,
      verifyEndpointSignature: (_, _) async => true,
    );
    recovery = CallEndpointRecovery(
      budget: newBudget(),
      admitted: admitted,
      bindingCurrent: () => bindingCurrent,
    );
  }
  final FakeAsync async;
  bool current = true;
  bool bindingCurrent = true;
  int episodeGeneration = 0;
  final roster = _Roster('valid');
  final wake = _WakeStore('valid');
  final authority = _Authority();
  late final CallEndpointResolver resolver;
  late CallEndpointRecovery recovery;
  final admitted = const ResolvedCallEndpoint(
    accountPeerId: _account,
    devicePeerId: _device,
    signingPublicKey: 'signing-key',
    mlKemPublicKey: 'kem-key',
    admissionAuthority: (fingerprint: 'friend', relationshipRevision: 1),
    deviceKeyEpoch: 1,
    preferenceEpoch: 1,
    platform: CallEndpointPlatform.android,
    expiresAtMs: _now + 60000,
    routingHandle: '0123456789abcdef0123456789abcdef',
    wakeHandle: 'fedcba9876543210fedcba9876543210',
    capabilities: {'voice_call_v1', 'video_call_v2'},
  );
  CallRecoveryBudget newBudget() {
    final generation = ++episodeGeneration;
    return CallRecoveryBudget(
      duration: const Duration(seconds: 15),
      monotonicNow: () => async.elapsed,
      isCurrent: () => current && episodeGeneration == generation,
    );
  }

  Future<ResolvedCallEndpoint> resolve({CallEndpointRecovery? episode}) =>
      resolveProductionCallEndpoint(
        contactAccountPeerId: _account,
        resolver: resolver,
        rosterProvider: roster,
        authorityClient: authority,
        receivedCallWakeHandleStore: wake,
        recovery: episode ?? recovery,
      );
}
