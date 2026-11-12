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
  int id = 1,
  bool ice = false,
  String? terminal,
  int expires = _start + 45000,
}) => CallSignalV2.fromMap({
  'schema': CallSignalV2.schema,
  'call_id': _call,
  'message_id': '33333333-3333-4333-8333-${id.toString().padLeft(12, '0')}',
  'event': terminal ?? (ice ? 'ice' : 'media_commit'),
  'sender_account_peer_id': 'sender-account',
  'sender_device_peer_id': 'sender-device',
  'recipient_account_peer_id': 'recipient-account',
  'recipient_device_peer_id': 'recipient-device',
  'sender_sequence': id,
  'ice_generation': 0,
  'created_at_ms': _start,
  'expires_at_ms': expires,
  'payload': terminal != null
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
}) => ResolvedCallEndpoint(
  accountPeerId: 'recipient-account',
  devicePeerId: device,
  signingPublicKey: 'signing-public',
  mlKemPublicKey: 'kem-public',
  deviceKeyEpoch: 1,
  preferenceEpoch: 1,
  platform: CallEndpointPlatform.android,
  expiresAtMs: expires,
  routingHandle: '0123456789abcdef0123456789abcdef',
  wakeHandle: 'fedcba9876543210fedcba9876543210',
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
  int now = _start;
  bool current = true;
  int networkChecks = 0;
  int authorizations = 0;
  Future<bool> Function()? network;
  Future<bool> Function()? authority;
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
    networkEffectsAllowed: () {
      networkChecks++;
      return network?.call() ?? Future.value(true);
    },
    nowMs: () => now,
  );
  Future<bool> authorize() {
    authorizations++;
    return authority?.call() ?? Future.value(true);
  }

  Future<CallSignalTransmissionRetry> prepare({
    CallSignalV2? signal,
    ResolvedCallEndpoint? endpoint,
    bool enabled = true,
  }) => service.prepareV2(
    signal: signal ?? _signal(),
    callHandle: _handle,
    endpoint: endpoint ?? _endpoint(),
    senderSigningPrivateKey: 'private-signing-key',
    authorize: authorize,
    canApply: () => current,
    videoEnabled: enabled,
  );
  Future<CallSignalTransportResult> send(CallSignalTransmissionRetry retry) =>
      retry.retry(authorize: authorize, canApply: () => current);
  void expectNoWrites() {
    expect(direct.envelopes, isEmpty);
    expect(mailbox.requests, isEmpty);
  }
}

void main() {
  late _Rig r;
  setUp(() => r = _Rig());
  tearDown(() => r.service.close());

  test(
    'disabled by default: no network, authorization, encryption or write',
    () async {
      await expectLater(
        r.service.prepareV2(
          signal: _signal(),
          callHandle: _handle,
          endpoint: _endpoint(),
          senderSigningPrivateKey: 'private-signing-key',
          authorize: r.authorize,
          canApply: () => true,
        ),
        throwsA(isA<CallSignalingException>()),
      );
      expect(r.networkChecks, 0);
      expect(r.authorizations, 0);
      expect(r.crypto.encryptions, 0);
      r.expectNoWrites();
    },
  );

  test('prepare encodes once without writes; success replay keeps exact bytes and message ID', () async {
    final retry = await r.prepare();
    r.expectNoWrites();
    expect(r.crypto.encryptions, 1);
    expect((await r.send(retry)).delivered, isTrue);
    expect(retry.isAvailable, isTrue);
    expect((await r.send(retry)).delivered, isTrue);
    expect(r.direct.envelopes, hasLength(2));
    expect(r.direct.envelopes.toSet(), hasLength(1));
    expect(r.mailbox.requests.map((e) => e.envelopeJson).toSet(), {
      r.direct.envelopes.singleOrNull ?? r.direct.envelopes.first,
    });
    expect(r.mailbox.requests.map((e) => e.messageId).toSet(), {
      _signal().messageId,
    });
    expect(r.crypto.encryptions, 1);
    expect(r.service.pendingTerminalRetryCount, 0);
  });

  test(
    'both legs fail then explicit retry reuses bytes without terminal retry',
    () async {
      r.direct.action = () async => _failed;
      r.mailbox.action = (_) async => throw StateError('offline');
      final retry = await r.prepare();
      await expectLater(r.send(retry), throwsA(isA<CallSignalingException>()));
      expect(retry.isAvailable, isTrue);
      expect(r.service.pendingTerminalRetryCount, 0);
      r.direct.action = null;
      r.mailbox.action = null;
      expect((await r.send(retry)).delivered, isTrue);
      expect(r.crypto.encryptions, 1);
      expect(r.direct.envelopes.toSet(), hasLength(1));
    },
  );

  for (final heldDirect in [true, false]) {
    test(
      'independent legs and pending sibling reuse: heldDirect=$heldDirect',
      () async {
        final direct = Completer<CallDirectSendResult>();
        final mailbox = Completer<CallMailboxStoreResult>();
        if (heldDirect) {
          r.direct.action = () => direct.future;
        } else {
          r.mailbox.action = (_) => mailbox.future;
        }
        final retry = await r.prepare();
        expect((await r.send(retry)).delivered, isTrue);
        expect(r.direct.envelopes, hasLength(1));
        expect(r.mailbox.requests, hasLength(1));
        expect((await r.send(retry)).delivered, isTrue);
        expect(r.direct.envelopes, hasLength(heldDirect ? 1 : 2));
        expect(r.mailbox.requests, hasLength(heldDirect ? 2 : 1));
        if (heldDirect) {
          direct.complete(_accepted);
        } else {
          mailbox.complete(r.mailbox.result(r.mailbox.requests.first));
        }
      },
    );
  }

  for (final caps in [
    <String>{},
    {'voice_call_v1'},
    {'video_call_v2'},
  ]) {
    test('requires both verified endpoint capabilities: $caps', () async {
      await expectLater(
        r.prepare(endpoint: _endpoint(capabilities: caps)),
        throwsA(isA<CallSignalingException>()),
      );
      expect(r.crypto.encryptions, 0);
      r.expectNoWrites();
    });
  }
  test('recipient mismatch fails before encryption', () async {
    await expectLater(
      r.prepare(endpoint: _endpoint(device: 'other-device')),
      throwsA(isA<CallSignalingException>()),
    );
    expect(r.crypto.encryptions, 0);
    r.expectNoWrites();
  });
  for (final endpointExpiry in [true, false]) {
    test(
      'expired ${endpointExpiry ? 'endpoint' : 'signal'} fails before encryption',
      () async {
        await expectLater(
          r
              .prepare(
                endpoint: _endpoint(
                  expires: endpointExpiry ? _start : _start + 45000,
                ),
                signal: _signal(
                  expires: endpointExpiry ? _start + 45000 : _start + 1,
                ),
              )
              .then((value) {
                // The signal starts valid, then expires before its first write.
                r.now++;
                return r.send(value);
              }),
          throwsA(isA<CallSignalingException>()),
        );
        if (endpointExpiry) expect(r.crypto.encryptions, 0);
        r.expectNoWrites();
      },
    );
  }

  for (final boundary in ['network', 'authority', 'crypto']) {
    test(
      'ownership lost during $boundary preparation wait prevents writes',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        Future<bool> wait() async {
          entered.complete();
          await release.future;
          return true;
        }

        if (boundary == 'network') r.network = wait;
        if (boundary == 'authority') r.authority = wait;
        if (boundary == 'crypto')
          r.crypto.wait = () async {
            entered.complete();
            await release.future;
          };
        final pending = r.prepare();
        final rejected = expectLater(
          pending,
          throwsA(isA<CallSignalingException>()),
        );
        await entered.future;
        r.current = false;
        release.complete();
        await rejected;
        r.expectNoWrites();
      },
    );
  }

  test('expiry during encryption prevents retained transmission', () async {
    r.crypto.wait = () async {
      r.now += 45000;
    };
    await expectLater(r.prepare(), throwsA(isA<CallSignalingException>()));
    expect(r.service.pendingTransmissionRetryCount, 0);
    r.expectNoWrites();
  });

  for (final boundary in ['network', 'authority']) {
    test('expiry during retry $boundary wait prevents both writes', () async {
      final retry = await r.prepare();
      Future<bool> expire() async {
        r.now += 45000;
        return true;
      }

      if (boundary == 'network') r.network = expire;
      if (boundary == 'authority') r.authority = expire;
      await expectLater(r.send(retry), throwsA(isA<CallSignalingException>()));
      expect(retry.isAvailable, isFalse);
      r.expectNoWrites();
    });
  }

  test('recheck authority immediately before each leg write', () async {
    final retry = await r.prepare();
    r.direct.action = () async {
      r.current = false;
      return _accepted;
    };
    await expectLater(r.send(retry), throwsA(isA<CallSignalingException>()));
    expect(r.direct.envelopes, hasLength(1));
    expect(r.mailbox.requests, isEmpty);
  });

  test('four attempt cap does not reencrypt or renew deadline', () async {
    final retry = await r.prepare();
    for (var i = 0; i < 4; i++) {
      await r.send(retry);
    }
    expect(retry.isAvailable, isFalse);
    await expectLater(r.send(retry), throwsA(isA<CallSignalingException>()));
    expect(r.direct.envelopes, hasLength(4));
    expect(r.crypto.encryptions, 1);
  });
  test(
    'successful replay cannot extend original 15 second custody deadline',
    () async {
      final retry = await r.prepare();
      await r.send(retry);
      r.now += 14999;
      await r.send(retry);
      r.now++;
      await expectLater(r.send(retry), throwsA(isA<CallSignalingException>()));
      expect(r.direct.envelopes, hasLength(2));
    },
  );
  test(
    'closed ID cannot be prepared again before original wire expiry',
    () async {
      final retry = await r.prepare();
      retry.close();
      await expectLater(r.prepare(), throwsA(isA<CallSignalingException>()));
      expect(r.crypto.encryptions, 1);
      r.expectNoWrites();
    },
  );
  test('reserve ID before asynchronous preparation so concurrent duplicate cannot encode', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    r.crypto.wait = () async {
      entered.complete();
      await release.future;
    };
    final first = r.prepare();
    await entered.future;
    await expectLater(r.prepare(), throwsA(isA<CallSignalingException>()));
    release.complete();
    await first;
    expect(r.crypto.encryptions, 1);
    r.expectNoWrites();
  });
  test('ICE churn cannot evict a selected transaction result', () async {
    final selected = await r.prepare();
    for (var i = 2; i < 10; i++) {
      await r.prepare(signal: _signal(id: i, ice: true));
    }
    expect(r.service.pendingTransmissionRetryCount, 4);
    expect(selected.isAvailable, isTrue);
    expect((await r.send(selected)).delivered, isTrue);
    expect(r.service.pendingTerminalRetryCount, 0);
  });
  test(
    'full protected custody refuses new ICE without displacing results',
    () async {
      final results = <CallSignalTransmissionRetry>[];
      for (var i = 1; i <= 4; i++) {
        results.add(await r.prepare(signal: _signal(id: i)));
      }
      await expectLater(
        r.prepare(signal: _signal(id: 5, ice: true)),
        throwsA(isA<CallSignalingException>()),
      );
      expect(results.every((r) => r.isAvailable), isTrue);
      expect(r.service.pendingTransmissionRetryCount, 4);
    },
  );
  for (final terminal in ['reject', 'terminate']) {
    test(
      '$terminal takes custody despite full protected optional results',
      () async {
        final optional = <CallSignalTransmissionRetry>[];
        for (var i = 1; i <= 4; i++) {
          optional.add(await r.prepare(signal: _signal(id: i)));
        }
        final retry = await r.prepare(
          signal: _signal(id: 5, terminal: terminal),
        );
        expect((await r.send(retry)).delivered, isTrue);
        expect(r.service.pendingTransmissionRetryCount, 4);
        expect(optional.where((entry) => entry.isAvailable), hasLength(3));
        expect(r.mailbox.requests.single.messageId, _signal(id: 5).messageId);
      },
    );
    test('$terminal retains exact bytes through optional ICE churn', () async {
      final retry = await r.prepare(signal: _signal(terminal: terminal));
      await r.send(retry);
      final envelope = r.direct.envelopes.single;
      for (var i = 2; i < 10; i++) {
        await r.prepare(signal: _signal(id: i, ice: true));
      }
      expect(retry.isAvailable, isTrue);
      expect((await r.send(retry)).delivered, isTrue);
      expect(r.direct.envelopes, [envelope, envelope]);
      expect(r.mailbox.requests.map((entry) => entry.messageId).toSet(), {
        _signal().messageId,
      });
    });
  }
  test('optional identity tombstones cannot consume terminal admission reserve', () async {
    for (var i = 1; i <= 128; i++) {
      try {
        await r.prepare(signal: _signal(id: i, ice: true));
      } on CallSignalingException {
        // Bounded optional capacity may refuse work before terminal admission.
      }
    }
    final terminal = await r.prepare(
      signal: _signal(id: 129, terminal: 'terminate'),
    );
    expect((await r.send(terminal)).delivered, isTrue);
  });
  test('stop retries fences prepared and new transmissions', () async {
    final retry = await r.prepare();
    r.service.stopRetries();
    await expectLater(r.send(retry), throwsA(isA<CallSignalingException>()));
    await expectLater(
      r.prepare(signal: _signal(id: 2)),
      throwsA(isA<CallSignalingException>()),
    );
    r.expectNoWrites();
    expect(r.crypto.encryptions, 1);
  });
}
