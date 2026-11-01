import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/app/bootstrap/production_call_signaling_graph.dart';
import 'package:flutter_app/app/bootstrap/call_wake_contact_key_backfill.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/application/outgoing_call_capability.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/call/diagnostics/call_diagnostics.dart';
import 'package:flutter_app/features/call/domain/received_call_wake_handle_store.dart';
import 'package:flutter_app/features/call/infrastructure/android_call_lifecycle_adapter.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_app/features/call/infrastructure/production_call_endpoint_resolution.dart';
import 'package:flutter_app/features/call/infrastructure/call_trusted_roster_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';

const _nowMs = 5_000_000;
const _accountPeerId = 'private-contact-account';
const _devicePeerId = 'private-contact-device';
const _routingHandle = '0123456789abcdef0123456789abcdef';
const _wakeHandle = 'fedcba9876543210fedcba9876543210';

TrustedCallDeviceAuthority _trustedDevice() => const TrustedCallDeviceAuthority(
  accountPeerId: _accountPeerId,
  devicePeerId: _devicePeerId,
  linked: true,
  deviceKeyEpoch: 7,
  signingPublicKey: 'private-signing-public-key',
  mlKemPublicKey: 'private-mlkem-public-key',
);

CallTrustedRosterSnapshot _roster({
  bool accepted = true,
  bool blocked = false,
}) => CallTrustedRosterSnapshot(
  contactAccountPeerId: _accountPeerId,
  contactAccepted: accepted,
  contactBlocked: blocked,
  devices: <TrustedCallDeviceAuthority>[_trustedDevice()],
);

SignedCallEndpointRecord _endpoint({
  int expiresAtMs = _nowMs + 60_000,
  String signature = 'private-signature',
}) {
  final record = CallEndpointRecord(
    accountPeerId: _accountPeerId,
    devicePeerId: _devicePeerId,
    capabilities: <String>{CallEndpointResolver.voiceCapability},
    platform: CallEndpointPlatform.ios,
    expiresAtMs: expiresAtMs,
    preferenceEpoch: 3,
    deviceKeyEpoch: 7,
    routingHandle: _routingHandle,
  );
  return SignedCallEndpointRecord(
    record: record,
    signature: signature,
    canonicalRecordBase64: base64Encode(
      utf8.encode(record.canonicalRecordJson),
    ),
  );
}

CallWakeHandleGrant _grant({
  String devicePeerId = _devicePeerId,
  int expiresAtMs = _nowMs + 30_000,
}) => CallWakeHandleGrant(
  handle: _wakeHandle,
  recipientDevicePeerId: devicePeerId,
  deviceKeyEpoch: 7,
  generation: 2,
  issuedAtMs: _nowMs - 1_000,
  expiresAtMs: expiresAtMs,
);

CallEndpointResolver _resolver() => CallEndpointResolver(
  nowMs: () => _nowMs,
  verifyEndpointSignature: (endpoint, signingPublicKey) async =>
      endpoint.signature == 'private-signature' &&
      signingPublicKey == 'private-signing-public-key',
);

final class _RosterProvider implements CallTrustedRosterProvider {
  _RosterProvider({required this.snapshot, this.error});

  CallTrustedRosterSnapshot snapshot;
  final Object? error;

  @override
  Future<CallTrustedRosterSnapshot> loadForContact(String peerId) async {
    if (error case final error?) throw error;
    return snapshot;
  }

  @override
  Future<TrustedCallDeviceAuthority?> resolveAuthenticatedTransport(
    String authenticatedTransportPeerId,
  ) async => null;
}

final class _ReceivedStore implements ReceivedCallWakeHandleStore {
  _ReceivedStore({required this.grant, this.error});

  CallWakeHandleGrant? grant;
  final Object? error;

  @override
  Future<CallWakeHandleGrant?> readForIssuer(String issuerAccountPeerId) async {
    if (error case final error?) throw error;
    return grant;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Authority implements CallAuthorityClient {
  _Authority({required this.endpoint, this.error});

  SignedCallEndpointRecord? endpoint;
  final Object? error;
  int reads = 0;

  @override
  Future<SignedCallEndpointRecord?> getEndpoint(String accountPeerId) async {
    reads++;
    if (error case final error?) throw error;
    return endpoint;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<({bool available, List<Map<String, dynamic>> results})> _probe({
  bool networkAllowed = true,
  bool Function()? networkGate,
  CallTrustedRosterProvider? rosterProvider,
  ReceivedCallWakeHandleStore? receivedStore,
  CallAuthorityClient? authority,
  Future<bool> Function(String contactAccountPeerId)?
  ensureReceivedCallWakeHandle,
  RepairCallEndpoint? repairMissingEndpoint,
  OutgoingCallStartRequest? request,
}) async {
  final events = <Map<String, dynamic>>[];
  debugSetFlowEventSink(events.add);
  try {
    final available = await probeProductionCallEndpointAvailability(
      networkEffectsAllowed: networkGate ?? () => networkAllowed,
      contactAccountPeerId: _accountPeerId,
      resolver: _resolver(),
      rosterProvider: rosterProvider ?? _RosterProvider(snapshot: _roster()),
      authorityClient: authority ?? _Authority(endpoint: _endpoint()),
      receivedCallWakeHandleStore:
          receivedStore ?? _ReceivedStore(grant: _grant()),
      ensureReceivedCallWakeHandle: ensureReceivedCallWakeHandle,
      repairMissingEndpoint: repairMissingEndpoint,
      request: request,
    );
    return (
      available: available,
      results: events
          .where((event) => event['event'] == 'CALL_ENDPOINT_RESOLUTION_RESULT')
          .toList(growable: false),
    );
  } finally {
    debugSetFlowEventSink(null);
  }
}

void _expectSingleResult(
  ({bool available, List<Map<String, dynamic>> results}) actual, {
  required bool available,
  required String stage,
  required String outcome,
  required String reason,
}) {
  expect(actual.available, available);
  expect(actual.results, hasLength(1));
  final details = Map<String, dynamic>.from(
    actual.results.single['details'] as Map,
  );
  expect(details.keys.toSet(), <String>{'stage', 'outcome', 'reason'});
  expect(details, <String, Object?>{
    'stage': stage,
    'outcome': outcome,
    'reason': reason,
  });

  final encoded = jsonEncode(actual.results.single);
  for (final privateValue in <String>[
    _accountPeerId,
    _devicePeerId,
    _routingHandle,
    _wakeHandle,
    'private-signing-public-key',
    'private-mlkem-public-key',
    'private-signature',
    'private dependency exploded',
  ]) {
    expect(encoded, isNot(contains(privateValue)));
  }
}

void main() {
  tearDown(() => debugSetFlowEventSink(null));

  Future<CallDiagnostics> installDiagnostics() async {
    final diagnostics = await CallDiagnostics.installForTesting();
    addTearDown(() async {
      await diagnostics.setEnabled(false);
      await diagnostics.dispose();
    });
    return diagnostics;
  }

  Future<List<Map<String, dynamic>>> exportedEvents(
    CallDiagnostics diagnostics,
  ) async {
    final exported = await diagnostics.exportPreview();
    for (final privateValue in <String>[
      _accountPeerId,
      _devicePeerId,
      _routingHandle,
      _wakeHandle,
      'private-signing-public-key',
      'private-mlkem-public-key',
      'private-signature',
      _endpoint().canonicalRecordBase64,
    ]) {
      expect(exported, isNot(contains(privateValue)));
    }
    return (jsonDecode(exported)['events'] as List)
        .map((event) => Map<String, dynamic>.from(event as Map))
        .toList();
  }

  for (final deviceCount in [1, 32]) {
    test('CALL-INCIDENT exported endpoint input is bounded for '
        '$deviceCount trusted devices', () async {
      final diagnostics = await installDiagnostics();
      final traceId = diagnostics.beginAttempt();
      await diagnostics.runWithTrace(
        traceId,
        () => _probe(
          rosterProvider: _RosterProvider(
            snapshot: CallTrustedRosterSnapshot(
              contactAccountPeerId: _accountPeerId,
              contactAccepted: true,
              contactBlocked: false,
              devices: List.filled(deviceCount, _trustedDevice()),
            ),
          ),
        ),
      );
      final events = await exportedEvents(diagnostics);
      final snapshots = events
          .where(
            (event) =>
                event['traceId'] == traceId &&
                event['stage'] == 'preflight' &&
                event['action'] == 'snapshot',
          )
          .toList();
      expect(snapshots, hasLength(1));
      expect(snapshots.single['values'], {
        'contactAccepted': true,
        'contactBlocked': false,
        'trustedDeviceCount': deviceCount > 16 ? 16 : deviceCount,
        'relayEndpointPresent': true,
        'wakeHandleGrantPresent': true,
      });
    });
  }

  for (final repair in ['missing', 'expired', 'declined', 'canceled']) {
    test('CALL-INCIDENT endpoint repair exports $repair outcome', () async {
      final diagnostics = await installDiagnostics();
      final traceId = diagnostics.beginAttempt();
      final authority = _Authority(
        endpoint: repair == 'expired' ? _endpoint(expiresAtMs: _nowMs) : null,
      );
      var repairs = 0;
      final result = await diagnostics.runWithTrace(
        traceId,
        () => _probe(
          authority: authority,
          request: OutgoingCallStartRequest(),
          repairMissingEndpoint: (_, {beforeRequest}) async {
            await beforeRequest?.call();
            repairs++;
            if (repair == 'canceled') throw const OutgoingCallStartCanceled();
            if (repair == 'declined') return false;
            authority.endpoint = _endpoint();
            return true;
          },
        ),
      );
      expect(repairs, 1);
      expect(result.available, repair == 'missing' || repair == 'expired');
      final events = await exportedEvents(diagnostics);
      final recovery = events
          .where(
            (event) =>
                event['traceId'] == traceId &&
                event['stage'] == 'preflight' &&
                event['action'] == 'recover',
          )
          .toList();
      expect(recovery.map((event) => event['outcome']), [
        'started',
        repair == 'canceled'
            ? 'canceled'
            : repair == 'declined'
            ? 'failed'
            : 'ok',
      ]);
      if (repair == 'declined') {
        expect(
          events.any((event) => event['reason'] == 'endpoint_not_found'),
          isTrue,
        );
      } else {
        expect(
          events.where(
            (event) =>
                event['traceId'] == traceId &&
                event['outcome'] == 'preflight_failed',
          ),
          isEmpty,
        );
      }
    });
  }

  test(
    'CALL-INCIDENT passive probes add no input or repair orphan events',
    () async {
      final diagnostics = await installDiagnostics();
      await _probe();
      final events = await exportedEvents(diagnostics);
      expect(
        events.where(
          (event) =>
              event['stage'] == 'preflight' &&
              (event['action'] == 'snapshot' || event['action'] == 'recover'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'availability reports a closed network gate without resolving',
    () async {
      final actual = await _probe(networkAllowed: false);

      _expectSingleResult(
        actual,
        available: false,
        stage: 'network_gate',
        outcome: 'blocked',
        reason: 'network_effects_blocked',
      );
    },
  );

  test('availability identifies each dependency load failure', () async {
    final privateError = StateError('private dependency exploded');
    final cases =
        <
          ({
            String stage,
            CallTrustedRosterProvider? roster,
            ReceivedCallWakeHandleStore? received,
            CallAuthorityClient? authority,
          })
        >[
          (
            stage: 'trusted_roster_load',
            roster: _RosterProvider(snapshot: _roster(), error: privateError),
            received: null,
            authority: null,
          ),
          (
            stage: 'received_wake_handle_load',
            roster: null,
            received: _ReceivedStore(grant: _grant(), error: privateError),
            authority: null,
          ),
          (
            stage: 'relay_endpoint_load',
            roster: null,
            received: null,
            authority: _Authority(endpoint: _endpoint(), error: privateError),
          ),
        ];

    for (final entry in cases) {
      final actual = await _probe(
        rosterProvider: entry.roster,
        receivedStore: entry.received,
        authority: entry.authority,
      );
      _expectSingleResult(
        actual,
        available: false,
        stage: entry.stage,
        outcome: 'error',
        reason: 'dependency_error',
      );
    }
  });

  test('availability reports the typed resolver rejection', () async {
    final actual = await _probe(
      rosterProvider: _RosterProvider(snapshot: _roster(accepted: false)),
    );

    _expectSingleResult(
      actual,
      available: false,
      stage: 'endpoint_resolve',
      outcome: 'unavailable',
      reason: 'notAccepted',
    );
  });

  test('availability recovers a missing received wake handle once', () async {
    final receivedStore = _ReceivedStore(grant: null);
    var recoveryCalls = 0;

    final actual = await _probe(
      request: OutgoingCallStartRequest(),
      receivedStore: receivedStore,
      ensureReceivedCallWakeHandle: (contactAccountPeerId) async {
        expect(contactAccountPeerId, _accountPeerId);
        recoveryCalls++;
        receivedStore.grant = _grant();
        return true;
      },
    );

    expect(recoveryCalls, 1);
    _expectSingleResult(
      actual,
      available: true,
      stage: 'ready',
      outcome: 'available',
      reason: 'none',
    );
  });

  for (final initialEndpoint in ['missing', 'expired']) {
    test(
      'explicit endpoint repair with current grant recovers $initialEndpoint endpoint',
      () async {
        final receivedStore = _ReceivedStore(grant: _grant());
        final authority = _Authority(
          endpoint: initialEndpoint == 'missing'
              ? null
              : _endpoint(expiresAtMs: _nowMs),
        );
        var repairSends = 0;
        final recovery = ReceivedCallWakeHandleRecoveryCoordinator(
          receivedCallWakeHandleStore: receivedStore,
          nowMs: () => _nowMs,
          requestRecovery:
              ({required contactAccountPeerId, beforeRequest}) async {
                expect(contactAccountPeerId, _accountPeerId);
                repairSends++;
                authority.endpoint = _endpoint();
              },
        );
        final actual = await _probe(
          authority: authority,
          receivedStore: receivedStore,
          ensureReceivedCallWakeHandle: recovery.ensureCurrentGrantFor,
          repairMissingEndpoint: recovery.requestEndpointRepairFor,
          request: OutgoingCallStartRequest(),
        );
        expect(repairSends, 1);
        expect(actual.available, isTrue);
      },
    );
  }

  for (final hasGrant in [false, true]) {
    test(
      'passive endpoint probe preserves grant backfill with grant=$hasGrant',
      () async {
        final receivedStore = _ReceivedStore(grant: hasGrant ? _grant() : null);
        var grantBackfillSends = 0;
        var endpointRepairRequests = 0;
        final recovery = ReceivedCallWakeHandleRecoveryCoordinator(
          receivedCallWakeHandleStore: receivedStore,
          nowMs: () => _nowMs,
          requestRecovery:
              ({required contactAccountPeerId, beforeRequest}) async {
                grantBackfillSends++;
              },
        );
        final actual = await _probe(
          authority: _Authority(endpoint: null),
          receivedStore: receivedStore,
          ensureReceivedCallWakeHandle: recovery.ensureCurrentGrantFor,
          repairMissingEndpoint: (peerId, {beforeRequest}) async {
            endpointRepairRequests++;
            return recovery.requestEndpointRepairFor(
              peerId,
              beforeRequest: beforeRequest,
            );
          },
        );
        expect(grantBackfillSends, hasGrant ? 0 : 1);
        expect(endpointRepairRequests, 0);
        expect(actual.available, isFalse);
      },
    );
  }

  for (final rejection in [
    'blocked',
    'unaccepted',
    'wrong-grant-device',
    'expired-grant',
    'invalid-stale-signature',
    'network-denied',
  ]) {
    test(
      'endpoint repair rejects $rejection authority without a send',
      () async {
        var repairCalls = 0;
        final actual = await _probe(
          networkAllowed: rejection != 'network-denied',
          rosterProvider: _RosterProvider(
            snapshot: _roster(
              accepted: rejection != 'unaccepted',
              blocked: rejection == 'blocked',
            ),
          ),
          receivedStore: _ReceivedStore(
            grant: _grant(
              devicePeerId: rejection == 'wrong-grant-device'
                  ? 'other-device'
                  : _devicePeerId,
              expiresAtMs: rejection == 'expired-grant'
                  ? _nowMs
                  : _nowMs + 30_000,
            ),
          ),
          authority: _Authority(
            endpoint: rejection == 'invalid-stale-signature'
                ? _endpoint(expiresAtMs: _nowMs, signature: 'invalid')
                : null,
          ),
          request: OutgoingCallStartRequest(),
          repairMissingEndpoint: (_, {beforeRequest}) async {
            repairCalls++;
            return true;
          },
        );
        expect(actual.available, isFalse);
        expect(repairCalls, 0);
      },
    );
  }

  for (final completion in [
    'published',
    'timeout',
    'canceled',
    'blocked',
    'network-denied',
  ]) {
    test('endpoint repair bounded rechecks finish on $completion', () {
      fakeAsync((time) {
        final authority = _Authority(endpoint: null);
        final roster = _RosterProvider(snapshot: _roster());
        final request = OutgoingCallStartRequest();
        var networkAllowed = true;
        var repairCalls = 0;
        bool? available;
        unawaited(
          _probe(
            authority: authority,
            rosterProvider: roster,
            networkGate: () => networkAllowed,
            request: request,
            repairMissingEndpoint: (_, {beforeRequest}) async {
              await beforeRequest?.call();
              repairCalls++;
              return true;
            },
          ).then((result) => available = result.available),
        );
        time.flushMicrotasks();
        expect(repairCalls, 1);
        expect(available, isNull);
        if (completion == 'published') authority.endpoint = _endpoint();
        if (completion == 'canceled') request.cancel();
        if (completion == 'blocked') roster.snapshot = _roster(blocked: true);
        if (completion == 'network-denied') networkAllowed = false;
        time.elapse(Duration(seconds: completion == 'timeout' ? 10 : 1));
        time.flushMicrotasks();
        expect(available, completion == 'published');
        expect(repairCalls, 1);
        final reads = authority.reads;
        authority.endpoint = _endpoint();
        time.elapse(const Duration(seconds: 20));
        time.flushMicrotasks();
        expect(authority.reads, reads);
        expect(repairCalls, 1);
      });
    });
  }

  test(
    'recovered endpoint does not finish the outgoing trace as failed',
    () async {
      final diagnostics = await CallDiagnostics.installForTesting();
      addTearDown(() async {
        await diagnostics.setEnabled(false);
        await diagnostics.dispose();
      });
      final traceId = diagnostics.beginAttempt();
      final authority = _Authority(endpoint: null);
      final result = await diagnostics.runWithTrace(
        traceId,
        () => _probe(
          authority: authority,
          request: OutgoingCallStartRequest(),
          repairMissingEndpoint: (_, {beforeRequest}) async {
            await beforeRequest?.call();
            authority.endpoint = _endpoint();
            return true;
          },
        ),
      );
      expect(result.available, isTrue);
      final events = await diagnostics.eventsForTesting();
      expect(
        events.where(
          (event) =>
              event['traceId'] == traceId && event['stage'] == 'terminal',
        ),
        isEmpty,
      );
      expect(
        events.where(
          (event) =>
              event['traceId'] == traceId &&
              event['outcome'] == 'preflight_failed',
        ),
        isEmpty,
      );
    },
  );

  test('availability emits one identifier-free ready result', () async {
    final actual = await _probe();

    _expectSingleResult(
      actual,
      available: true,
      stage: 'ready',
      outcome: 'available',
      reason: 'none',
    );
  });

  test(
    'call capability advertisement exposes identifier-free stage results',
    () {
      final source = File(
        'lib/app/bootstrap/production_call_signaling_graph.dart',
      ).readAsStringSync();

      expect(source, contains("event: 'CALL_CAPABILITY_ADVERTISEMENT_RESULT'"));
      for (final stage in <String>[
        'network_gate',
        'voip_token',
        'wake_authority',
        'identity_keys',
        'endpoint_sign',
        'endpoint_publish',
        'ready',
      ]) {
        expect(source, contains("'$stage'"));
      }
      expect(source, contains("'stage': stage"));
      expect(source, contains("'outcome': outcome"));
    },
  );

  test('media bundle close failure names the failing stage', () async {
    final events = <Map<String, dynamic>>[];
    debugSetFlowEventSink(events.add);
    List<Map<String, dynamic>> stageEvents() => events
        .where((event) => event['event'] == 'CALL_MEDIA_CLOSE_FAILURE_STAGE')
        .toList(growable: false);
    Future<void> noop() async {}

    await expectLater(
      debugCloseCallMediaBundle(
        closeInterruptionCoordinator: noop,
        closeAudioController: noop,
        audioCleanupFailed: () => true,
        closeNegotiationExecutor: noop,
      ),
      throwsA(isA<AndroidCallLifecycleException>()),
    );
    expect(stageEvents(), hasLength(1));
    expect(stageEvents().single['details'], <String, Object?>{
      'stage': 'audio_cleanup',
    });

    events.clear();
    await expectLater(
      debugCloseCallMediaBundle(
        closeInterruptionCoordinator: noop,
        closeAudioController: noop,
        audioCleanupFailed: () => false,
        closeNegotiationExecutor: () async {
          throw StateError('private engine release failure');
        },
      ),
      throwsA(isA<StateError>()),
    );
    expect(stageEvents(), hasLength(1));
    expect(stageEvents().single['details'], <String, Object?>{
      'stage': 'engine_release',
    });
    expect(jsonEncode(events), isNot(contains('private engine release')));

    events.clear();
    await debugCloseCallMediaBundle(
      closeInterruptionCoordinator: noop,
      closeAudioController: noop,
      audioCleanupFailed: () => false,
      closeNegotiationExecutor: noop,
    );
    expect(stageEvents(), isEmpty);
  });
}
