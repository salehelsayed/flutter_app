import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/application/call_signaling_service.dart';
import 'package:flutter_app/features/call/domain/call_signal_v2.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_app/features/call/infrastructure/call_mailbox_client.dart';
import 'package:flutter_app/features/call/infrastructure/p2p_call_transport.dart';
import 'package:flutter_app/features/call/infrastructure/secure_call_envelope_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/call/application/call_signaling_context_store.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/infrastructure/production_call_v2_signaling_adapter.dart';

const _start = 2000000;
const _call = '22222222-2222-4222-8222-222222222222';
const _handle = '66666666-6666-4666-8666-666666666666';
const _accepted = CallDirectSendResult(
  outcome: CallDirectTransportOutcome.acceptedBytes,
  transportAcknowledged: true,
  route: CallDirectRoute.direct,
);
const _failed = CallDirectSendResult(
  outcome: CallDirectTransportOutcome.failed,
  transportAcknowledged: false,
  route: CallDirectRoute.unknown,
);

CallSignalV2 _signal({
  int id = 2,
  bool invite = false,
  bool ice = false,
  String? terminal,
  int expires = _start + 45000,
}) => CallSignalV2.fromMap({
  'schema': CallSignalV2.schema,
  'call_id': _call,
  'message_id': '33333333-3333-4333-8333-${id.toString().padLeft(12, '0')}',
  'event': invite ? 'invite' : terminal ?? (ice ? 'ice' : 'media_commit'),
  'sender_account_peer_id': 'sender-account',
  'sender_device_peer_id': 'sender-device',
  'recipient_account_peer_id': 'recipient-account',
  'recipient_device_peer_id': 'recipient-device',
  'sender_sequence': id,
  'ice_generation': 0,
  'created_at_ms': _start,
  'expires_at_ms': expires,
  'payload': invite
      ? {
          'media': 'audio',
          'camera': 'off',
          'capabilities': ['audio', 'video'],
        }
      : terminal != null
      ? {'reason': 'unsupported'}
      : ice
      ? {
          'negotiation_id': '44444444-4444-4444-8444-444444444444',
          'candidate': 'private-candidate',
          'media_id': null,
          'media_line_index': null,
        }
      : {
          'switch_id': '55555555-5555-4555-8555-555555555555',
          'media_revision': 1,
          'media': 'video',
        },
}, videoEnabled: true);

ResolvedCallEndpoint _endpoint({
  Set<String> capabilities = const {'voice_call_v1', 'video_call_v2'},
  int expires = _start + 45000,
  String device = 'recipient-device',
  int epoch = 1,
  int preference = 1,
  String wake = 'fedcba9876543210fedcba9876543210',
  CallAdmissionAuthorityWitness? witness,
}) => ResolvedCallEndpoint(
  accountPeerId: 'recipient-account',
  devicePeerId: device,
  signingPublicKey: 'signing-public',
  mlKemPublicKey: 'kem-public',
  deviceKeyEpoch: epoch,
  preferenceEpoch: preference,
  admissionAuthority: witness,
  platform: CallEndpointPlatform.android,
  expiresAtMs: expires,
  routingHandle: '0123456789abcdef0123456789abcdef',
  wakeHandle: wake,
  capabilities: capabilities,
);

final class _Crypto implements CallEnvelopeCrypto {
  int encryptions = 0;
  Future<void> Function()? wait;
  @override
  Future<CallCiphertext> encrypt({
    required String recipientMlKemPublicKey,
    required String plaintext,
  }) async {
    final count = ++encryptions;
    await wait?.call();
    return CallCiphertext(
      kem: base64Encode(utf8.encode('kem')),
      ciphertext: base64Encode(utf8.encode(plaintext)),
      nonce: base64Encode(utf8.encode('nonce-$count')),
    );
  }

  @override
  Future<String> sign({
    required String senderSigningPrivateKey,
    required String canonicalData,
  }) async => base64Encode(utf8.encode(canonicalData));
  @override
  Future<String> decrypt({
    required String ownMlKemSecretKey,
    required CallCiphertext ciphertext,
  }) => throw UnimplementedError();
  @override
  Future<bool> verify({
    required String senderSigningPublicKey,
    required String canonicalData,
    required String signature,
  }) async => true;
}

final class _Direct implements CallDirectTransport {
  final envelopes = <String>[];
  Future<CallDirectSendResult> Function()? action;
  @override
  Future<CallDirectSendResult> send({
    required String recipientDevicePeerId,
    required String envelopeJson,
  }) {
    envelopes.add(envelopeJson);
    return action?.call() ?? Future.value(_accepted);
  }
}

final class _Mailbox implements CallMailboxClient {
  final requests = <CallMailboxStoreRequest>[];
  Future<CallMailboxStoreResult> Function(CallMailboxStoreRequest)? action;
  @override
  Future<CallMailboxStoreResult> store(CallMailboxStoreRequest request) {
    requests.add(request);
    return action?.call(request) ?? Future.value(result(request));
  }

  CallMailboxStoreResult result(CallMailboxStoreRequest request) =>
      CallMailboxStoreResult(
        status: CallMailboxStoreStatus.stored,
        receiptAtMs: _start,
        expiresAtMs: request.expiresAtMs,
        eventCount: 1,
        totalBytes: 100,
        pendingHandles: 1,
      );
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

final class _Rig {
  _Rig() {
    admitted = endpoint;
    contexts.storeOutgoingV2(
      invite: _signal(id: 1, invite: true),
      callHandle: _handle,
    );
  }

  int now = _start;
  bool current = true;
  int resolutions = 0;
  int keyLoads = 0;
  String signingKey = 'private-signing-key';
  Object? resolutionError;
  Future<void>? endpointGate;
  Future<void>? keyGate;
  ResolvedCallEndpoint endpoint = _endpoint();
  late final ResolvedCallEndpoint admitted;
  final contexts = CallSignalingContextStore(videoEnabled: true);
  final crypto = _Crypto();
  final direct = _Direct();
  final mailbox = _Mailbox();
  late final service = CallSignalingService(
    codec: SecureCallEnvelopeCodec(
      crypto: crypto,
      nowMs: () => now,
      videoEnabled: true,
    ),
    directTransport: direct,
    mailboxClient: mailbox,
    networkEffectsAllowed: () async => true,
    nowMs: () => now,
  );
  late final adapter = ProductionCallV2SignalingAdapter(
    signalingService: service,
    contextStore: contexts,
    resolveCurrentEndpoint: resolve,
    loadSenderSigningPrivateKey: loadKey,
    nowMs: () => now,
    videoEnabled: true,
  );

  Future<ResolvedCallEndpoint> resolve(String account) async {
    resolutions++;
    await endpointGate;
    if (resolutionError case final Object error) {
      throw error;
    }
    return endpoint;
  }

  Future<String> loadKey() async {
    keyLoads++;
    await keyGate;
    return signingKey;
  }

  Future<PreparedCallV2Signal> prepare({
    CallSignalV2? signal,
    String callHandle = _handle,
  }) => adapter.prepare(
    signal: signal ?? _signal(),
    callHandle: callHandle,
    admittedEndpoint: admitted,
    canApply: () => current,
  );

  Future<CallSignalTransportResult> send(PreparedCallV2Signal prepared) =>
      prepared.transmit(canApply: () => current);

  void expectNoWrites() {
    expect(direct.envelopes, isEmpty);
    expect(mailbox.requests, isEmpty);
  }

  void close() {
    adapter.close();
    service.close();
  }
}

void main() {
  late _Rig r;
  setUp(() => r = _Rig());
  tearDown(() => r.close());
  final rejected = throwsA(isA<CallSignalingException>());

  test(
    'default-off adapter performs no endpoint/key/crypto/transport work',
    () async {
      final disabled = ProductionCallV2SignalingAdapter(
        signalingService: r.service,
        contextStore: r.contexts,
        resolveCurrentEndpoint: r.resolve,
        loadSenderSigningPrivateKey: r.loadKey,
        nowMs: () => r.now,
      );
      await expectLater(
        disabled.prepare(
          signal: _signal(),
          callHandle: _handle,
          admittedEndpoint: r.admitted,
          canApply: () => true,
        ),
        rejected,
      );
      expect(r.resolutions, 0);
      expect(r.keyLoads, 0);
      expect(r.crypto.encryptions, 0);
      r.expectNoWrites();
      disabled.close();
    },
  );

  test(
    'preparation seals once without writes, then exact owner can transmit',
    () async {
      final prepared = await r.prepare();
      expect(prepared.isAvailable, isTrue);
      expect(r.crypto.encryptions, 1);
      r.expectNoWrites();
      final sent = await r.send(prepared);
      await sent.mailboxStoreSettled;
      expect(sent.delivered, isTrue);
      expect(r.direct.envelopes, hasLength(1));
      expect(r.mailbox.requests, hasLength(1));
    },
  );

  test(
    'same immutable ID shares its preparation Future before the first await',
    () async {
      final first = r.prepare();
      final second = r.prepare(signal: _signal());
      expect(identical(first, second), isTrue);
      final results = await Future.wait([first, second]);
      expect(identical(results[0], results[1]), isTrue);
      expect(r.crypto.encryptions, 1);
      r.expectNoWrites();
    },
  );

  test(
    'changed payload under the same ID cannot replace prepared custody',
    () async {
      final original = await r.prepare();
      final changed = CallSignalV2.fromMap({
        ..._signal().toMap(),
        'payload': {
          'switch_id': '55555555-5555-4555-8555-555555555555',
          'media_revision': 1,
          'media': 'audio',
        },
      }, videoEnabled: true);
      await expectLater(r.prepare(signal: changed), rejected);
      expect(original.isAvailable, isTrue);
      expect((await r.send(original)).delivered, isTrue);
      expect(r.crypto.encryptions, 1);
    },
  );

  test(
    'failed preparation remains the same failed Future and never reseals',
    () async {
      r.resolutionError = const CallEndpointResolutionException(
        CallEndpointResolutionCode.unavailable,
      );
      final first = r.prepare();
      await expectLater(first, rejected);
      final resolutions = r.resolutions;
      r.resolutionError = null;
      final second = r.prepare();
      expect(identical(first, second), isTrue);
      await expectLater(second, rejected);
      expect(r.resolutions, resolutions);
      expect(r.crypto.encryptions, 0);
      r.expectNoWrites();
    },
  );

  for (final binding in ['missing', 'v1', 'handle', 'peer']) {
    test('refuses $binding context binding before preparation I/O', () async {
      if (binding != 'handle') {
        r.contexts.purge(CallId.parse(_call));
      }
      if (binding == 'v1') {
        r.contexts.storeOutgoing(
          callId: CallId.parse(_call),
          callHandle: _handle,
          localAccountPeerId: 'sender-account',
          localDevicePeerId: 'sender-device',
          remoteAccountPeerId: 'recipient-account',
          remoteDevicePeerId: 'recipient-device',
        );
      }
      if (binding == 'peer') {
        final invite = _signal(id: 1, invite: true);
        r.contexts.storeOutgoingV2(
          invite: CallSignalV2.fromMap({
            ...invite.toMap(),
            'recipient_device_peer_id': 'different-device',
          }, videoEnabled: true),
          callHandle: _handle,
        );
      }
      await expectLater(
        r.prepare(
          callHandle: binding == 'handle'
              ? '77777777-7777-4777-8777-777777777777'
              : _handle,
        ),
        rejected,
      );
      expect(r.resolutions, 0);
      expect(r.keyLoads, 0);
      expect(r.crypto.encryptions, 0);
      r.expectNoWrites();
    });
  }

  for (final boundary in ['endpoint', 'key', 'crypto']) {
    test(
      'owner retirement during $boundary await cannot publish custody',
      () async {
        final gate = Completer<void>();
        switch (boundary) {
          case 'endpoint':
            r.endpointGate = gate.future;
          case 'key':
            r.keyGate = gate.future;
          case 'crypto':
            r.crypto.wait = () => gate.future;
        }
        final pending = expectLater(r.prepare(), rejected);
        await pumpEventQueue(times: 3);
        r.current = false;
        gate.complete();
        await pending;
        r.expectNoWrites();
        expect(r.service.pendingTransmissionRetryCount, 0);
      },
    );
  }

  test(
    'successful replay uses identical sealed bytes and fresh authority',
    () async {
      final prepared = await r.prepare();
      final first = await r.send(prepared);
      await first.mailboxStoreSettled;
      final checks = r.resolutions;
      final keyLoads = r.keyLoads;
      final second = await r.send(prepared);
      await second.mailboxStoreSettled;
      expect(r.crypto.encryptions, 1);
      expect(r.direct.envelopes, hasLength(2));
      expect(r.direct.envelopes[0], r.direct.envelopes[1]);
      expect(r.mailbox.requests, hasLength(2));
      expect(r.resolutions, greaterThan(checks));
      expect(r.keyLoads, greaterThan(keyLoads));
    },
  );

  test(
    'transient authority lookup refusal retains bytes for a later retry',
    () async {
      final prepared = await r.prepare();
      r.resolutionError = const CallEndpointResolutionException(
        CallEndpointResolutionCode.unavailable,
      );
      await expectLater(r.send(prepared), rejected);
      expect(prepared.isAvailable, isTrue);
      r.expectNoWrites();
      r.resolutionError = null;
      expect((await r.send(prepared)).delivered, isTrue);
      expect(r.crypto.encryptions, 1);
    },
  );

  test(
    'transport failure retries the same envelope without new preparation',
    () async {
      final prepared = await r.prepare();
      r.direct.action = () async => _failed;
      r.mailbox.action = (_) async =>
          throw StateError('synthetic mailbox outage');
      await expectLater(r.send(prepared), rejected);
      expect(prepared.isAvailable, isTrue);
      r.direct.action = null;
      r.mailbox.action = null;
      expect((await r.send(prepared)).delivered, isTrue);
      expect(r.direct.envelopes, hasLength(2));
      expect(r.direct.envelopes.first, r.direct.envelopes.last);
      expect(r.crypto.encryptions, 1);
    },
  );

  for (final change in [
    'device',
    'keyEpoch',
    'preference',
    'wake',
    'capability',
    'relationship',
  ]) {
    test(
      'fresh $change revocation prevents writes of prepared bytes',
      () async {
        final prepared = await r.prepare();
        r.endpoint = switch (change) {
          'device' => _endpoint(device: 'different-device'),
          'keyEpoch' => _endpoint(epoch: 2),
          'preference' => _endpoint(preference: 2),
          'wake' => _endpoint(wake: '0123456789abcdef0123456789abcdef'),
          'capability' => _endpoint(capabilities: {'voice_call_v1'}),
          _ => _endpoint(
            witness: (
              fingerprint: 'different-contact-authority',
              relationshipRevision: 2,
            ),
          ),
        };
        await expectLater(r.send(prepared), rejected);
        expect(prepared.isAvailable, isFalse);
        r.expectNoWrites();
        expect(r.crypto.encryptions, 1);
      },
    );
  }

  test('signing-key rotation cannot send or revive old signed bytes', () async {
    final prepared = await r.prepare();
    r.signingKey = 'rotated-private-key';
    await expectLater(r.send(prepared), rejected);
    r.signingKey = 'private-signing-key';
    await expectLater(r.send(prepared), rejected);
    expect(prepared.isAvailable, isFalse);
    r.expectNoWrites();
    expect(r.crypto.encryptions, 1);
  });

  test(
    'refreshed endpoint expiry is rechecked after local-key await',
    () async {
      final prepared = await r.prepare();
      final gate = Completer<void>();
      r.endpoint = _endpoint(expires: _start + 5);
      r.keyGate = gate.future;
      final pending = expectLater(r.send(prepared), rejected);
      await pumpEventQueue(times: 3);
      r.now += 6;
      gate.complete();
      await pending;
      r.expectNoWrites();
    },
  );

  test(
    'retired optional ID stays closed even when its caller asks again',
    () async {
      final future = r.prepare();
      final prepared = await future;
      r.adapter.retireCall(CallId.parse(_call));
      expect(prepared.isAvailable, isFalse);
      final again = r.prepare();
      expect(identical(again, future), isTrue);
      await expectLater(r.send(await again), rejected);
      expect(r.crypto.encryptions, 1);
      r.expectNoWrites();
    },
  );

  test(
    'terminal custody survives context purge without recreating a context',
    () async {
      final prepared = await r.prepare(signal: _signal(terminal: 'terminate'));
      r.adapter.retireCall(CallId.parse(_call));
      r.contexts.purge(CallId.parse(_call));
      expect((await r.send(prepared)).delivered, isTrue);
      expect(r.contexts.read(CallId.parse(_call)), isNull);
      expect(r.crypto.encryptions, 1);
    },
  );

  test(
    'terminal custody cannot bind to replacement context with different peers',
    () async {
      final prepared = await r.prepare(signal: _signal(terminal: 'terminate'));
      r.contexts.purge(CallId.parse(_call));
      r.contexts.storeOutgoingV2(
        invite: CallSignalV2.fromMap({
          ..._signal(id: 1, invite: true).toMap(),
          'recipient_device_peer_id': 'replacement-device',
        }, videoEnabled: true),
        callHandle: _handle,
      );
      await expectLater(r.send(prepared), rejected);
      expect(
        r.contexts.read(CallId.parse(_call))!.remoteDevicePeerId,
        'replacement-device',
      );
      r.expectNoWrites();
    },
  );

  test(
    'close during sealing releases pending custody and suppresses writes',
    () async {
      final gate = Completer<void>();
      r.crypto.wait = () => gate.future;
      final pending = expectLater(r.prepare(), rejected);
      await pumpEventQueue(times: 3);
      r.adapter.close();
      gate.complete();
      await pending;
      expect(r.service.pendingTransmissionRetryCount, 0);
      r.expectNoWrites();
    },
  );

  test('closed handle is returned from cache without resealing', () async {
    final future = r.prepare();
    final prepared = await future;
    prepared.close();
    expect(identical(r.prepare(), future), isTrue);
    expect(prepared.isAvailable, isFalse);
    await expectLater(r.send(prepared), rejected);
    expect(r.crypto.encryptions, 1);
  });

  test(
    'expired message ID cannot acquire a fresh lifetime within replay window',
    () async {
      final prepared = await r.prepare();
      r.now += 50000;
      await expectLater(
        r.prepare(signal: _signal(expires: r.now + 10000)),
        rejected,
      );
      expect(prepared.isAvailable, isFalse);
      expect(r.crypto.encryptions, 1);
      r.expectNoWrites();
    },
  );

  test('optional churn reserves four terminal identities and never reseals an evicted ID', () async {
    final firstFuture = r.prepare(signal: _signal(id: 2, ice: true));
    final first = await firstFuture;
    for (var id = 3; id < 126; id++) {
      await r.prepare(signal: _signal(id: id, ice: true));
    }
    expect(first.isAvailable, isFalse);
    expect(
      identical(r.prepare(signal: _signal(id: 2, ice: true)), firstFuture),
      isTrue,
    );
    final encryptions = r.crypto.encryptions;
    await expectLater(r.prepare(signal: _signal(id: 126, ice: true)), rejected);
    expect(r.crypto.encryptions, encryptions);
    for (var id = 200; id < 204; id++) {
      final terminal = await r.prepare(
        signal: _signal(id: id, terminal: 'terminate'),
      );
      expect(terminal.isAvailable, isTrue);
    }
    await expectLater(
      r.prepare(signal: _signal(id: 204, terminal: 'terminate')),
      rejected,
    );
    r.expectNoWrites();
  });

  test(
    'adapter and prepared diagnostics omit identities, authority and payload',
    () async {
      final prepared = await r.prepare();
      final text = '${r.adapter} $prepared';
      for (final secret in [
        _call,
        _handle,
        'recipient-account',
        'private-signing-key',
        '55555555-5555-4555-8555-555555555555',
      ]) {
        expect(text, isNot(contains(secret)));
      }
    },
  );
}
