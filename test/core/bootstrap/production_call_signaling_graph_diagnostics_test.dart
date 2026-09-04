import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/app/bootstrap/production_call_signaling_graph.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/call/domain/received_call_wake_handle_store.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_app/features/call/infrastructure/call_trusted_roster_provider.dart';
import 'package:flutter_test/flutter_test.dart';

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

CallTrustedRosterSnapshot _roster({bool accepted = true}) =>
    CallTrustedRosterSnapshot(
      contactAccountPeerId: _accountPeerId,
      contactAccepted: accepted,
      contactBlocked: false,
      devices: <TrustedCallDeviceAuthority>[_trustedDevice()],
    );

SignedCallEndpointRecord _endpoint() {
  const record = CallEndpointRecord(
    accountPeerId: _accountPeerId,
    devicePeerId: _devicePeerId,
    capabilities: <String>{CallEndpointResolver.voiceCapability},
    platform: CallEndpointPlatform.ios,
    expiresAtMs: _nowMs + 60_000,
    preferenceEpoch: 3,
    deviceKeyEpoch: 7,
    routingHandle: _routingHandle,
  );
  return SignedCallEndpointRecord(
    record: record,
    signature: 'private-signature',
    canonicalRecordBase64: base64Encode(
      utf8.encode(record.canonicalRecordJson),
    ),
  );
}

CallWakeHandleGrant _grant() => CallWakeHandleGrant(
  handle: _wakeHandle,
  recipientDevicePeerId: _devicePeerId,
  deviceKeyEpoch: 7,
  generation: 2,
  issuedAtMs: _nowMs - 1_000,
  expiresAtMs: _nowMs + 30_000,
);

CallEndpointResolver _resolver() => CallEndpointResolver(
  nowMs: () => _nowMs,
  verifyEndpointSignature: (endpoint, signingPublicKey) async =>
      endpoint.signature == 'private-signature' &&
      signingPublicKey == 'private-signing-public-key',
);

final class _RosterProvider implements CallTrustedRosterProvider {
  _RosterProvider({required this.snapshot, this.error});

  final CallTrustedRosterSnapshot snapshot;
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

  final SignedCallEndpointRecord? endpoint;
  final Object? error;

  @override
  Future<SignedCallEndpointRecord?> getEndpoint(String accountPeerId) async {
    if (error case final error?) throw error;
    return endpoint;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<({bool available, List<Map<String, dynamic>> results})> _probe({
  bool networkAllowed = true,
  CallTrustedRosterProvider? rosterProvider,
  ReceivedCallWakeHandleStore? receivedStore,
  CallAuthorityClient? authority,
  Future<bool> Function(String contactAccountPeerId)?
  ensureReceivedCallWakeHandle,
}) async {
  final events = <Map<String, dynamic>>[];
  debugSetFlowEventSink(events.add);
  try {
    final available = await probeProductionCallEndpointAvailability(
      networkEffectsAllowed: () => networkAllowed,
      contactAccountPeerId: _accountPeerId,
      resolver: _resolver(),
      rosterProvider: rosterProvider ?? _RosterProvider(snapshot: _roster()),
      authorityClient: authority ?? _Authority(endpoint: _endpoint()),
      receivedCallWakeHandleStore:
          receivedStore ?? _ReceivedStore(grant: _grant()),
      ensureReceivedCallWakeHandle: ensureReceivedCallWakeHandle,
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
}
