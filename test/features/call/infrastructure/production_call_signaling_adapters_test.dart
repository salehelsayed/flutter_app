import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_control_effect_executor.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/call_negotiation_effect_executor.dart';
import 'package:flutter_app/features/call/application/call_signaling_context_store.dart';
import 'package:flutter_app/features/call/application/call_signaling_service.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_app/features/call/infrastructure/call_mailbox_client.dart';
import 'package:flutter_app/features/call/infrastructure/p2p_call_transport.dart';
import 'package:flutter_app/features/call/infrastructure/production_call_signaling_adapters.dart';
import 'package:flutter_app/features/call/infrastructure/secure_call_envelope_codec.dart';
import 'package:flutter_test/flutter_test.dart';

const _nowMs = 2_000_000;
final _now = DateTime.fromMillisecondsSinceEpoch(_nowMs, isUtc: true);
final _callId = CallId.parse('11111111-1111-4111-8111-111111111111');
const _callHandle = '22222222-2222-4222-8222-222222222222';

void main() {
  group('ProductionCallControlSignalingAdapter', () {
    test('prepares a fresh opaque binding with audio-only metadata', () async {
      final harness = _ServiceHarness();
      addTearDown(harness.dispose);
      final authority = _EndpointAuthority(_endpoint());
      final ids = _Ids(<String>[
        '33333333-3333-4333-8333-333333333333',
        '44444444-4444-4444-8444-444444444444',
      ]);
      final adapter = ProductionCallControlSignalingAdapter(
        signalingService: harness.service,
        resolveCurrentEndpoint: authority.resolve,
        loadSenderSigningPrivateKey: _loadSigningKey,
        callHandleSource: ids.next,
      );

      final first = await adapter.prepareOutgoingInvite(_outgoingPreparing());
      final second = await adapter.prepareOutgoingInvite(_outgoingPreparing());

      expect(authority.requestedAccounts, <String>[
        'remote-account',
        'remote-account',
      ]);
      expect(first.remoteAccountPeerId, 'remote-account');
      expect(first.remoteDevicePeerId, 'remote-device');
      expect(CallId.tryParse(first.callHandle), isNotNull);
      expect(first.callHandle, isNot(_callId.value));
      expect(second.callHandle, isNot(first.callHandle));
      expect(first.nextSenderSequence, 1);
      expect(first.iceGeneration, 0);
      expect(first.invitePayload, <String, Object?>{
        'capabilities': <Object?>['audio'],
        'metadata': <String, Object?>{'media': 'audio', 'video': false},
      });
      final encoded = jsonEncode(first.invitePayload).toLowerCase();
      expect(encoded, isNot(contains('sdp')));
      expect(encoded, isNot(contains('candidate')));
      expect(encoded, isNot(contains('ice')));
    });

    test(
      're-resolves the exact endpoint for send and fails closed after rotation',
      () async {
        final harness = _ServiceHarness();
        addTearDown(harness.dispose);
        final authority = _EndpointAuthority(_endpoint());
        final adapter = ProductionCallControlSignalingAdapter(
          signalingService: harness.service,
          resolveCurrentEndpoint: authority.resolve,
          loadSenderSigningPrivateKey: _loadSigningKey,
          callHandleSource: _Ids(<String>[
            '33333333-3333-4333-8333-333333333333',
          ]).next,
        );
        final prepared = await adapter.prepareOutgoingInvite(
          _outgoingPreparing(),
        );
        authority.current = _endpoint(devicePeerId: 'rotated-device');

        await expectLater(
          adapter.send(
            signal: _controlSignal(
              recipientDevicePeerId: prepared.remoteDevicePeerId,
            ),
            callHandle: prepared.callHandle,
          ),
          throwsA(
            isA<CallControlSignalingPortException>().having(
              (error) => error.code,
              'code',
              CallControlSignalingPortErrorCode.endpointMismatch,
            ),
          ),
        );

        expect(authority.calls, 2);
        expect(harness.direct.calls, 0);
        expect(harness.mailbox.stores, 0);
      },
    );

    test(
      'maps transmit receipts without recursively dispatching coordinator events',
      () async {
        final harness = _ServiceHarness(
          directResult: const CallDirectSendResult(
            outcome: CallDirectTransportOutcome.acceptedBytes,
            transportAcknowledged: true,
            route: CallDirectRoute.circuitRelay,
          ),
        );
        addTearDown(harness.dispose);
        await _prepareCoordinator(harness.coordinator);
        final before = List<String>.of(
          harness.coordinator.activeSession!.recentEventIds,
        );
        final authority = _EndpointAuthority(_endpoint());
        final adapter = ProductionCallControlSignalingAdapter(
          signalingService: harness.service,
          resolveCurrentEndpoint: authority.resolve,
          loadSenderSigningPrivateKey: _loadSigningKey,
        );

        final result = await adapter.send(
          signal: _controlSignal(),
          callHandle: _callHandle,
        );

        expect(result.directAccepted, isTrue);
        expect(result.mailboxStored, isTrue);
        expect(result.directRoute, CallRouteClass.circuitRelay);
        expect(authority.calls, 1);
        expect(harness.direct.calls, 1);
        expect(harness.mailbox.stores, 1);
        expect(harness.coordinator.activeSession!.recentEventIds, before);
        expect(
          harness.coordinator.activeSession!.mailboxCustodyConfirmed,
          false,
        );
      },
    );

    test('propagates direct-first pending mailbox settlement', () async {
      final storeGate = Completer<void>();
      final harness = _ServiceHarness(mailboxStoreGate: storeGate.future);
      addTearDown(harness.dispose);
      final adapter = ProductionCallControlSignalingAdapter(
        signalingService: harness.service,
        resolveCurrentEndpoint: _EndpointAuthority(_endpoint()).resolve,
        loadSenderSigningPrivateKey: _loadSigningKey,
      );

      final result = await adapter.send(
        signal: _controlSignal(),
        callHandle: _callHandle,
      );
      var mailboxSettled = false;
      final settlement = result.mailboxStoreSettled;
      unawaited(settlement.then<void>((_) => mailboxSettled = true));
      await Future<void>.delayed(Duration.zero);
      expect(result.directAccepted, isTrue);
      expect(result.mailboxStored, isFalse);
      expect(mailboxSettled, isFalse);

      storeGate.complete();
      await settlement;

      expect(mailboxSettled, isTrue);
      expect(harness.mailbox.stores, 1);
    });

    test('maps arbitrary failures to fixed-shape redacted errors', () async {
      final harness = _ServiceHarness();
      addTearDown(harness.dispose);
      final authority = _EndpointAuthority(_endpoint())
        ..error = StateError(
          'secret-peer secret-handle secret-key secret-sdp secret-candidate',
        );
      final adapter = ProductionCallControlSignalingAdapter(
        signalingService: harness.service,
        resolveCurrentEndpoint: authority.resolve,
        loadSenderSigningPrivateKey: _loadSigningKey,
      );

      Object? caught;
      try {
        await adapter.send(signal: _controlSignal(), callHandle: _callHandle);
      } catch (error) {
        caught = error;
      }

      expect(caught, isA<CallControlSignalingPortException>());
      expect('$caught', 'CallControlSignalingPortException(endpointMismatch)');
      _expectRedacted('$caught $adapter');
    });
  });

  group('ProductionCallNegotiationSignalingAdapter', () {
    test(
      'uses context bindings and monotonic metadata for SDP, ICE, and restart',
      () async {
        final harness = _ServiceHarness();
        addTearDown(harness.dispose);
        final contextStore = _outgoingContext(nextSenderSequence: 7);
        final authority = _EndpointAuthority(_endpoint());
        final adapter = ProductionCallNegotiationSignalingAdapter(
          signalingService: harness.service,
          contextStore: contextStore,
          resolveCurrentEndpoint: authority.resolve,
          loadSenderSigningPrivateKey: _loadSigningKey,
          clock: () => _now,
          messageIdSource: _Ids(<String>[
            '50000000-0000-4000-8000-000000000001',
            '50000000-0000-4000-8000-000000000002',
            '50000000-0000-4000-8000-000000000003',
            '50000000-0000-4000-8000-000000000004',
            '50000000-0000-4000-8000-000000000005',
            '50000000-0000-4000-8000-000000000006',
          ]).next,
        );

        await adapter.sendDescription(
          callId: _callId,
          description: const CallSessionDescription(
            type: CallSessionDescriptionType.offer,
            value: 'secret-offer-sdp',
            fingerprint: 'secret-offer-fingerprint',
          ),
          iceGeneration: 1,
        );
        await adapter.sendDescription(
          callId: _callId,
          description: const CallSessionDescription(
            type: CallSessionDescriptionType.answer,
            value: 'secret-answer-sdp',
            fingerprint: 'secret-answer-fingerprint',
          ),
          iceGeneration: 1,
        );
        await adapter.sendCandidates(
          callId: _callId,
          candidates: const <CallIceCandidate>[
            CallIceCandidate(
              value: 'secret-candidate-one',
              mediaId: 'audio',
              mediaLineIndex: 0,
              iceGeneration: 2,
            ),
            CallIceCandidate(
              value: 'secret-candidate-two',
              mediaId: null,
              mediaLineIndex: null,
              iceGeneration: 2,
            ),
          ],
        );
        await adapter.sendIceRestart(callId: _callId, iceGeneration: 3);
        await adapter.sendDescription(
          callId: _callId,
          description: const CallSessionDescription(
            type: CallSessionDescriptionType.offer,
            value: 'secret-restart-offer-sdp',
            fingerprint: 'secret-restart-fingerprint',
          ),
          iceGeneration: 3,
        );

        final signals = harness.crypto.plaintexts
            .map(_decodeSignal)
            .toList(growable: false);
        expect(signals.map((signal) => signal.event), <CallSignalType>[
          CallSignalType.offer,
          CallSignalType.answer,
          CallSignalType.ice,
          CallSignalType.ice,
          CallSignalType.iceRestart,
          CallSignalType.offer,
        ]);
        expect(signals.map((signal) => signal.senderSequence), <int>[
          7,
          8,
          9,
          10,
          11,
          12,
        ]);
        expect(signals.map((signal) => signal.iceGeneration), <int>[
          1,
          1,
          2,
          2,
          3,
          3,
        ]);
        expect(
          signals.map((signal) => signal.expiresAtMs),
          everyElement(_nowMs + 40_000),
        );
        expect(signals[0].payload, <String, Object?>{
          'description': 'secret-offer-sdp',
          'fingerprint': 'secret-offer-fingerprint',
        });
        expect(signals[2].payload, <String, Object?>{
          'candidate': 'secret-candidate-one',
          'media_id': 'audio',
          'media_line_index': 0,
        });
        expect(signals[4].payload, isEmpty);
        expect(
          signals.every(
            (signal) =>
                signal.senderAccountPeerId == 'local-account' &&
                signal.senderDevicePeerId == 'local-device' &&
                signal.recipientAccountPeerId == 'remote-account' &&
                signal.recipientDevicePeerId == 'remote-device',
          ),
          isTrue,
        );
        expect(authority.calls, signals.length);
        expect(harness.direct.calls, signals.length);
        expect(harness.mailbox.stores, signals.length);
        expect(contextStore.read(_callId)?.nextSenderSequence, 13);
        expect(contextStore.read(_callId)?.iceGeneration, 3);
        _expectRedacted('$adapter');
      },
    );

    test('validates explicit signal lifetime overrides', () {
      final harness = _ServiceHarness();
      addTearDown(harness.dispose);

      ProductionCallNegotiationSignalingAdapter build(Duration lifetime) =>
          ProductionCallNegotiationSignalingAdapter(
            signalingService: harness.service,
            contextStore: _outgoingContext(),
            resolveCurrentEndpoint: _EndpointAuthority(_endpoint()).resolve,
            loadSenderSigningPrivateKey: _loadSigningKey,
            signalLifetime: lifetime,
          );

      expect(() => build(Duration.zero), throwsArgumentError);
      expect(
        () => build(
          SecureCallEnvelopeCodec.maximumPostconnectLifetime +
              const Duration(milliseconds: 1),
        ),
        throwsArgumentError,
      );
      expect(
        build(
          SecureCallEnvelopeCodec.maximumPostconnectLifetime,
        ).signalLifetime,
        SecureCallEnvelopeCodec.maximumPostconnectLifetime,
      );
    });

    test('answers from the authenticated incoming binding', () async {
      final harness = _ServiceHarness();
      addTearDown(harness.dispose);
      final store = CallSignalingContextStore();
      store.captureAuthenticated(
        signal: _incomingInvite(),
        callHandle: _callHandle,
      );
      final authority = _EndpointAuthority(_endpoint());
      final adapter = ProductionCallNegotiationSignalingAdapter(
        signalingService: harness.service,
        contextStore: store,
        resolveCurrentEndpoint: authority.resolve,
        loadSenderSigningPrivateKey: _loadSigningKey,
        clock: () => _now,
        messageIdSource: _Ids(<String>[
          '60000000-0000-4000-8000-000000000001',
        ]).next,
      );

      await adapter.sendDescription(
        callId: _callId,
        description: const CallSessionDescription(
          type: CallSessionDescriptionType.answer,
          value: 'secret-answer-sdp',
          fingerprint: 'secret-answer-fingerprint',
        ),
        iceGeneration: 0,
      );

      final signal = _decodeSignal(harness.crypto.plaintexts.single);
      expect(signal.senderAccountPeerId, 'local-account');
      expect(signal.senderDevicePeerId, 'local-device');
      expect(signal.recipientAccountPeerId, 'remote-account');
      expect(signal.recipientDevicePeerId, 'remote-device');
      expect(signal.senderSequence, 1);
      expect(signal.event, CallSignalType.answer);
    });

    test(
      'fails closed before transport when the current device no longer matches',
      () async {
        final harness = _ServiceHarness();
        addTearDown(harness.dispose);
        final authority = _EndpointAuthority(
          _endpoint(devicePeerId: 'rotated-device'),
        );
        final adapter = ProductionCallNegotiationSignalingAdapter(
          signalingService: harness.service,
          contextStore: _outgoingContext(),
          resolveCurrentEndpoint: authority.resolve,
          loadSenderSigningPrivateKey: _loadSigningKey,
          clock: () => _now,
        );

        Object? caught;
        try {
          await adapter.sendDescription(
            callId: _callId,
            description: const CallSessionDescription(
              type: CallSessionDescriptionType.offer,
              value: 'secret-sdp',
              fingerprint: 'secret-fingerprint',
            ),
            iceGeneration: 0,
          );
        } catch (error) {
          caught = error;
        }

        expect(caught, isA<CallNegotiationPortException>());
        expect('$caught', 'CallNegotiationPortException(signalingUnavailable)');
        expect(harness.crypto.plaintexts, isEmpty);
        expect(harness.direct.calls, 0);
        expect(harness.mailbox.stores, 0);
        _expectRedacted('$caught $adapter');
      },
    );
  });

  test('adapters use transmit and import no ordinary chat abstractions', () {
    const path =
        'lib/features/call/infrastructure/production_call_signaling_adapters.dart';
    final source = File(path).readAsStringSync();

    expect(source, contains('_signalingService.transmit('));
    expect(source, isNot(contains('_signalingService.send(')));
    for (final forbidden in const <String>[
      'features/conversation/',
      'pending_message_retrier',
      'message_outbox',
      'PendingMessageRetrier',
      'MessageRepository',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });
}

CallSessionSnapshot _outgoingPreparing() => CallSessionSnapshot.active(
  callId: _callId,
  contactPeerId: 'remote-account',
  direction: CallDirection.outgoing,
  state: CallState.preparing,
  callerAccountPeerId: 'local-account',
  callerDeviceId: 'local-device',
  startedAt: _now,
  observedAt: _now,
);

CallSignal _controlSignal({String recipientDevicePeerId = 'remote-device'}) =>
    CallSignal.create(
      callId: _callId,
      messageId: '70000000-0000-4000-8000-000000000001',
      event: CallSignalType.invite,
      senderAccountPeerId: 'local-account',
      senderDevicePeerId: 'local-device',
      recipientAccountPeerId: 'remote-account',
      recipientDevicePeerId: recipientDevicePeerId,
      senderSequence: 1,
      iceGeneration: 0,
      createdAtMs: _nowMs,
      expiresAtMs: _nowMs + 45_000,
    );

CallSignal _incomingInvite() => CallSignal.create(
  callId: _callId,
  messageId: '80000000-0000-4000-8000-000000000001',
  event: CallSignalType.invite,
  senderAccountPeerId: 'remote-account',
  senderDevicePeerId: 'remote-device',
  recipientAccountPeerId: 'local-account',
  recipientDevicePeerId: 'local-device',
  senderSequence: 4,
  iceGeneration: 0,
  createdAtMs: _nowMs,
  expiresAtMs: _nowMs + 45_000,
);

CallSignalingContextStore _outgoingContext({int nextSenderSequence = 1}) {
  final store = CallSignalingContextStore();
  store.storeOutgoing(
    callId: _callId,
    callHandle: _callHandle,
    localAccountPeerId: 'local-account',
    localDevicePeerId: 'local-device',
    remoteAccountPeerId: 'remote-account',
    remoteDevicePeerId: 'remote-device',
    nextSenderSequence: nextSenderSequence,
  );
  return store;
}

ResolvedCallEndpoint _endpoint({
  String accountPeerId = 'remote-account',
  String devicePeerId = 'remote-device',
}) => ResolvedCallEndpoint(
  accountPeerId: accountPeerId,
  devicePeerId: devicePeerId,
  signingPublicKey: 'secret-remote-signing-key',
  mlKemPublicKey: 'secret-remote-mlkem-key',
  deviceKeyEpoch: 2,
  preferenceEpoch: 3,
  platform: CallEndpointPlatform.android,
  expiresAtMs: _nowMs + 60_000,
  routingHandle: '0123456789abcdef0123456789abcdef',
  wakeHandle: 'fedcba9876543210fedcba9876543210',
);

Future<String> _loadSigningKey() async => 'secret-local-signing-key';

CallSignal _decodeSignal(String plaintext) =>
    CallSignal.fromMap(Map<String, Object?>.from(jsonDecode(plaintext) as Map));

void _expectRedacted(String value) {
  for (final forbidden in const <String>[
    'secret-peer',
    'secret-handle',
    'secret-key',
    'secret-sdp',
    'secret-offer',
    'secret-answer',
    'secret-candidate',
    'local-account',
    'local-device',
    'remote-account',
    'remote-device',
    _callHandle,
  ]) {
    expect(value, isNot(contains(forbidden)), reason: forbidden);
  }
}

Future<void> _prepareCoordinator(CallCoordinator coordinator) async {
  await coordinator.dispatch(
    CallEvent(
      type: CallEventType.place,
      eventId: 'place',
      occurredAt: _now,
      callId: _callId,
      contactPeerId: 'remote-account',
      localAccountPeerId: 'local-account',
      localDeviceId: 'local-device',
    ),
  );
  await coordinator.dispatch(
    CallEvent(
      type: CallEventType.outgoingInviteReady,
      eventId: 'invite-ready',
      occurredAt: _now,
      callId: _callId,
      contactPeerId: 'remote-account',
    ),
  );
}

final class _EndpointAuthority {
  _EndpointAuthority(this.current);

  ResolvedCallEndpoint current;
  Object? error;
  final List<String> requestedAccounts = <String>[];

  int get calls => requestedAccounts.length;

  Future<ResolvedCallEndpoint> resolve(String accountPeerId) async {
    requestedAccounts.add(accountPeerId);
    final currentError = error;
    if (currentError != null) throw currentError;
    return current;
  }
}

final class _Ids {
  _Ids(this.values);

  final List<String> values;
  int _index = 0;

  CallId next() => CallId.parse(values[_index++]);
}

final class _ServiceHarness {
  _ServiceHarness({
    CallDirectSendResult directResult = const CallDirectSendResult(
      outcome: CallDirectTransportOutcome.acceptedBytes,
      transportAcknowledged: true,
      route: CallDirectRoute.direct,
    ),
    Future<void>? mailboxStoreGate,
  }) : crypto = _CaptureCrypto(),
       direct = _Direct(directResult),
       mailbox = _Mailbox(mailboxStoreGate),
       coordinator = _coordinator() {
    service = CallSignalingService(
      codec: SecureCallEnvelopeCodec(crypto: crypto, nowMs: () => _nowMs),
      directTransport: direct,
      mailboxClient: mailbox,
      coordinator: coordinator,
      networkEffectsAllowed: () => true,
    );
  }

  final _CaptureCrypto crypto;
  final _Direct direct;
  final _Mailbox mailbox;
  final CallCoordinator coordinator;
  late final CallSignalingService service;

  Future<void> dispose() => coordinator.dispose();
}

final class _CaptureCrypto implements CallEnvelopeCrypto {
  final List<String> plaintexts = <String>[];

  @override
  Future<CallCiphertext> encrypt({
    required String recipientMlKemPublicKey,
    required String plaintext,
  }) async {
    plaintexts.add(plaintext);
    return CallCiphertext(
      kem: base64Encode(utf8.encode('kem')),
      ciphertext: base64Encode(utf8.encode(plaintext)),
      nonce: base64Encode(utf8.encode('nonce')),
    );
  }

  @override
  Future<String> decrypt({
    required String ownMlKemSecretKey,
    required CallCiphertext ciphertext,
  }) async => utf8.decode(base64Decode(ciphertext.ciphertext));

  @override
  Future<String> sign({
    required String senderSigningPrivateKey,
    required String canonicalData,
  }) async => base64Encode(utf8.encode('signature'));

  @override
  Future<bool> verify({
    required String senderSigningPublicKey,
    required String canonicalData,
    required String signature,
  }) async => true;
}

final class _Direct implements CallDirectTransport {
  _Direct(this.result);

  final CallDirectSendResult result;
  int calls = 0;

  @override
  Future<CallDirectSendResult> send({
    required String recipientDevicePeerId,
    required String envelopeJson,
  }) async {
    calls++;
    return result;
  }
}

final class _Mailbox implements CallMailboxClient {
  _Mailbox(this.storeGate);

  final Future<void>? storeGate;
  int stores = 0;

  @override
  Future<CallMailboxStoreResult> store(CallMailboxStoreRequest request) async {
    stores++;
    await storeGate;
    return CallMailboxStoreResult(
      status: CallMailboxStoreStatus.stored,
      receiptAtMs: _nowMs,
      expiresAtMs: request.expiresAtMs,
      eventCount: 1,
      totalBytes: 100,
      pendingHandles: 1,
    );
  }

  @override
  Future<int> ack({
    required String callHandle,
    required List<String> messageIds,
  }) => throw UnimplementedError();

  @override
  Future<bool> cancel({
    required String recipientDevicePeerId,
    required String callHandle,
  }) => throw UnimplementedError();

  @override
  Future<CallMailboxRetrieveResult> retrieve({
    String? callHandle,
    int limit = 64,
  }) => throw UnimplementedError();
}

CallCoordinator _coordinator() => CallCoordinator(
  reducer: const CallReducer(),
  cleanupCoordinator: CallCleanupCoordinator(const <CallCleanupStep>[]),
  historyProjector: CallHistoryProjector(_History()),
  clock: () => _now,
  idSource: () => _callId,
);

final class _History implements CallHistoryRepository {
  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async => null;

  @override
  Future<List<CallHistoryEntry>> listForContact(String peerId) async =>
      const <CallHistoryEntry>[];

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {}
}
