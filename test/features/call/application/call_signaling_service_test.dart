import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_control_effect_executor.dart';
import 'package:flutter_app/features/call/application/call_signaling_context_store.dart';
import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/call_signaling_service.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/diagnostics/call_diagnostics.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_app/features/call/infrastructure/call_mailbox_client.dart';
import 'package:flutter_app/features/call/infrastructure/p2p_call_transport.dart';
import 'package:flutter_app/features/call/infrastructure/production_call_signaling_adapters.dart';
import 'package:flutter_app/features/call/infrastructure/secure_call_envelope_codec.dart';
import 'package:flutter_test/flutter_test.dart';

const _nowMs = 2_000_000;
const _routingHandle = '0123456789abcdef0123456789abcdef';
const _wakeHandle = 'fedcba9876543210fedcba9876543210';
final _callId = CallId.parse('22222222-2222-4222-8222-222222222222');

final class _Crypto implements CallEnvelopeCrypto {
  @override
  Future<CallCiphertext> encrypt({
    required String recipientMlKemPublicKey,
    required String plaintext,
  }) async => CallCiphertext(
    kem: base64Encode(utf8.encode('kem')),
    ciphertext: base64Encode(utf8.encode(plaintext)),
    nonce: base64Encode(utf8.encode('nonce')),
  );

  @override
  Future<String> decrypt({
    required String ownMlKemSecretKey,
    required CallCiphertext ciphertext,
  }) async => utf8.decode(base64Decode(ciphertext.ciphertext));

  @override
  Future<String> sign({
    required String senderSigningPrivateKey,
    required String canonicalData,
  }) async =>
      base64Encode(utf8.encode('$senderSigningPrivateKey:$canonicalData'));

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
  String? envelope;

  @override
  Future<CallDirectSendResult> send({
    required String recipientDevicePeerId,
    required String envelopeJson,
  }) async {
    calls++;
    envelope = envelopeJson;
    return result;
  }
}

final class _ThrowingDirect implements CallDirectTransport {
  _ThrowingDirect({this.leakFailureDetails = false});

  final bool leakFailureDetails;
  int calls = 0;

  @override
  Future<CallDirectSendResult> send({
    required String recipientDevicePeerId,
    required String envelopeJson,
  }) async {
    calls++;
    if (leakFailureDetails) {
      throw StateError(
        'direct raw-error recipient=$recipientDevicePeerId '
        'envelope=$envelopeJson token=secret-token '
        'relay=/ip4/203.0.113.8/tcp/4001/p2p/relay-peer time=$_nowMs',
      );
    }
    throw StateError('direct transport unavailable');
  }
}

final class _CompleterDirect implements CallDirectTransport {
  final result = Completer<CallDirectSendResult>();
  int calls = 0;

  @override
  Future<CallDirectSendResult> send({
    required String recipientDevicePeerId,
    required String envelopeJson,
  }) {
    calls++;
    return result.future;
  }
}

final class _Mailbox implements CallMailboxClient {
  _Mailbox({required this.storeSucceeds, this.leakFailureDetails = false});

  final bool storeSucceeds;
  final bool leakFailureDetails;
  int stores = 0;
  CallMailboxStoreRequest? request;

  @override
  Future<CallMailboxStoreResult> store(CallMailboxStoreRequest request) async {
    stores++;
    this.request = request;
    if (!storeSucceeds) {
      if (leakFailureDetails) {
        throw StateError(
          'mailbox raw-error recipient=${request.recipientDevicePeerId} '
          'call=${request.callHandle} message=${request.messageId} '
          'wake=${request.wakeHandle} envelope=${request.envelopeJson} '
          'token=secret-token '
          'relay=/ip4/203.0.113.8/tcp/4001/p2p/relay-peer '
          'expires=${request.expiresAtMs}',
        );
      }
      throw StateError('mailbox down');
    }
    return const CallMailboxStoreResult(
      status: CallMailboxStoreStatus.stored,
      receiptAtMs: _nowMs,
      expiresAtMs: _nowMs + 45_000,
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

final class _CompleterMailbox implements CallMailboxClient {
  final result = Completer<CallMailboxStoreResult>();
  final operations = <String>[];
  int stores = 0;
  int cancels = 0;
  CallMailboxStoreRequest? request;

  @override
  Future<CallMailboxStoreResult> store(CallMailboxStoreRequest request) {
    stores++;
    this.request = request;
    return result.future;
  }

  void completeStore() {
    operations.add('store-settled');
    result.complete(
      const CallMailboxStoreResult(
        status: CallMailboxStoreStatus.stored,
        receiptAtMs: _nowMs,
        expiresAtMs: _nowMs + 45_000,
        eventCount: 1,
        totalBytes: 100,
        pendingHandles: 1,
      ),
    );
  }

  void failStore() {
    operations.add('store-failed');
    result.completeError(StateError('mailbox failed'));
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
  }) async {
    cancels++;
    operations.add('cancel');
    return true;
  }

  @override
  Future<CallMailboxRetrieveResult> retrieve({
    String? callHandle,
    int limit = 64,
  }) => throw UnimplementedError();
}

final class _History implements CallHistoryRepository {
  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async => null;

  @override
  Future<List<CallHistoryEntry>> listForContact(String peerId) async =>
      const [];

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {}
}

CallCoordinator _coordinator() => CallCoordinator(
  reducer: const CallReducer(),
  cleanupCoordinator: CallCleanupCoordinator(const <CallCleanupStep>[]),
  historyProjector: CallHistoryProjector(_History()),
  clock: () => DateTime.fromMillisecondsSinceEpoch(_nowMs, isUtc: true),
  idSource: () => _callId,
);

CallSignal _invite() => CallSignal.create(
  callId: _callId,
  messageId: '11111111-1111-4111-8111-111111111111',
  event: CallSignalType.invite,
  senderAccountPeerId: 'local-account',
  senderDevicePeerId: 'local-device',
  recipientAccountPeerId: 'remote-account',
  recipientDevicePeerId: 'remote-device',
  senderSequence: 1,
  iceGeneration: 0,
  createdAtMs: _nowMs,
  expiresAtMs: _nowMs + 45_000,
);

const _endpoint = ResolvedCallEndpoint(
  accountPeerId: 'remote-account',
  devicePeerId: 'remote-device',
  signingPublicKey: 'remote-signing',
  mlKemPublicKey: 'remote-mlkem',
  deviceKeyEpoch: 1,
  preferenceEpoch: 1,
  platform: CallEndpointPlatform.android,
  expiresAtMs: _nowMs + 60_000,
  routingHandle: _routingHandle,
  wakeHandle: _wakeHandle,
);

Future<void> _prepare(CallCoordinator coordinator) async {
  await coordinator.dispatch(
    CallEvent(
      type: CallEventType.place,
      eventId: 'place',
      occurredAt: DateTime.fromMillisecondsSinceEpoch(_nowMs, isUtc: true),
      callId: _callId,
      contactPeerId: 'remote-account',
      localAccountPeerId: 'local-account',
      localDeviceId: 'local-device',
      remoteAccountPeerId: 'remote-account',
      remoteDeviceId: 'remote-device',
    ),
  );
  await coordinator.dispatch(
    CallEvent(
      type: CallEventType.outgoingInviteReady,
      eventId: 'invite-ready',
      occurredAt: DateTime.fromMillisecondsSinceEpoch(_nowMs, isUtc: true),
      callId: _callId,
      contactPeerId: 'remote-account',
    ),
  );
}

void main() {
  test('offline terminate retries exact bytes after local context cleanup', () {
    fakeAsync((async) {
      final rig = _TerminalRetryRig(async);
      Object? failure;
      rig.send().catchError((Object error) {
        failure = error;
      });
      async.flushMicrotasks();
      expect(
        failure,
        isNotNull,
        reason: 'local failure must settle immediately',
      );
      expect(rig.mailbox.requests, hasLength(1));
      final original = rig.mailbox.requests.single;
      rig.contexts.purge(_callId);
      expect(rig.contexts.length, 0);
      rig.mailbox.online = true;
      async.elapse(const Duration(seconds: 3));
      expect(rig.mailbox.requests.length, greaterThan(1));
      final retry = rig.mailbox.requests.last;
      expect(retry.envelopeJson, original.envelopeJson);
      expect(rig.crypto.encryptions, 1);
      expect(retry.messageId, original.messageId);
      expect(retry.expiresAtMs, original.expiresAtMs);
      expect(retry.recipientDevicePeerId, original.recipientDevicePeerId);
      expect(retry.callHandle, original.callHandle);
      expect(
        rig.contexts.length,
        0,
        reason: 'retry must not resurrect context',
      );
    });
  });

  void failInitial(
    _TerminalRetryRig rig,
    FakeAsync async, {
    int lifetimeMs = 40_000,
    CallId? callId,
    CallSignalType event = CallSignalType.terminate,
  }) {
    var failed = false;
    rig.send(lifetimeMs: lifetimeMs, callId: callId, event: event).catchError((
      Object _,
    ) {
      failed = true;
    });
    async.flushMicrotasks();
    expect(failed, isTrue);
  }

  test('terminal retry rechecks refreshed endpoint expiry after key await', () {
    fakeAsync((async) {
      final rig = _TerminalRetryRig(async);
      failInitial(rig, async);
      rig.endpoint = ResolvedCallEndpoint(
        accountPeerId: _endpoint.accountPeerId,
        devicePeerId: _endpoint.devicePeerId,
        signingPublicKey: _endpoint.signingPublicKey,
        mlKemPublicKey: _endpoint.mlKemPublicKey,
        deviceKeyEpoch: _endpoint.deviceKeyEpoch,
        preferenceEpoch: _endpoint.preferenceEpoch,
        platform: _endpoint.platform,
        expiresAtMs: _nowMs + 1000,
        routingHandle: _endpoint.routingHandle,
        wakeHandle: _endpoint.wakeHandle,
      );
      final key = Completer<void>();
      rig.keyGate = key.future;
      async.elapse(const Duration(milliseconds: 1100));
      rig.mailbox.online = true;
      key.complete();
      async.flushMicrotasks();
      expect(rig.mailbox.requests, hasLength(1));
      expect(rig.service.pendingTerminalRetryCount, 0);
      rig.service.close();
    });
  });

  test('terminal retry succeeds once and releases retained bytes', () {
    fakeAsync((async) {
      final rig = _TerminalRetryRig(async);
      failInitial(rig, async);
      expect(rig.service.pendingTerminalRetryCount, 1);
      rig.mailbox.online = true;
      async.elapse(const Duration(seconds: 1));
      expect(rig.mailbox.requests, hasLength(2));
      expect(rig.service.pendingTerminalRetryCount, 0);
      async.elapse(const Duration(minutes: 1));
      expect(rig.mailbox.requests, hasLength(2));
    });
  });

  test(
    'terminal retry work and retention are capped after repeated failure',
    () {
      fakeAsync((async) {
        final rig = _TerminalRetryRig(async);
        failInitial(rig, async);
        async.elapse(const Duration(seconds: 16));
        expect(rig.mailbox.requests, hasLength(6));
        expect(rig.service.pendingTerminalRetryCount, 0);
        rig.mailbox.online = true;
        async.elapse(const Duration(minutes: 1));
        expect(rig.mailbox.requests, hasLength(6));
      });
    },
  );

  test('terminal retry never extends original message expiry', () {
    fakeAsync((async) {
      final rig = _TerminalRetryRig(async);
      failInitial(rig, async, lifetimeMs: 700);
      async.elapse(const Duration(milliseconds: 700));
      expect(rig.mailbox.requests, hasLength(2));
      expect(rig.service.pendingTerminalRetryCount, 0);
      rig.mailbox.online = true;
      async.elapse(const Duration(seconds: 10));
      expect(rig.mailbox.requests, hasLength(2));
      expect(rig.mailbox.requests.last.expiresAtMs, _nowMs + 700);
    });
  });

  test('terminal retry stops on account change or migration gate closure', () {
    for (final accountChange in [true, false]) {
      fakeAsync((async) {
        final rig = _TerminalRetryRig(async);
        failInitial(rig, async);
        if (accountChange) {
          rig.accountCurrent = false;
        } else {
          rig.networkAllowed = false;
        }
        rig.mailbox.online = true;
        async.elapse(const Duration(seconds: 1));
        expect(rig.service.pendingTerminalRetryCount, 0);
        rig.accountCurrent = true;
        rig.networkAllowed = true;
        async.elapse(const Duration(seconds: 15));
        expect(rig.mailbox.requests, hasLength(1));
      });
    }
  });

  test('terminal retry fails closed on recipient authority rotation', () {
    for (final field in ['device', 'key', 'epoch', 'preference', 'wake']) {
      fakeAsync((async) {
        final rig = _TerminalRetryRig(async);
        failInitial(rig, async);
        rig.endpoint = ResolvedCallEndpoint(
          accountPeerId: _endpoint.accountPeerId,
          devicePeerId: field == 'device'
              ? 'replacement'
              : _endpoint.devicePeerId,
          signingPublicKey: field == 'key'
              ? 'replacement'
              : _endpoint.signingPublicKey,
          mlKemPublicKey: _endpoint.mlKemPublicKey,
          deviceKeyEpoch: field == 'epoch' ? 2 : _endpoint.deviceKeyEpoch,
          preferenceEpoch: field == 'preference'
              ? 2
              : _endpoint.preferenceEpoch,
          platform: _endpoint.platform,
          expiresAtMs: _endpoint.expiresAtMs,
          routingHandle: _endpoint.routingHandle,
          wakeHandle: field == 'wake' ? 'a' * 32 : _endpoint.wakeHandle,
        );
        rig.mailbox.online = true;
        async.elapse(const Duration(seconds: 2));
        expect(rig.mailbox.requests, hasLength(1), reason: field);
        expect(rig.service.pendingTerminalRetryCount, 0, reason: field);
      });
    }
  });

  test(
    'terminal retry defers transient lookup but rejects explicit revocation',
    () {
      for (final code in [
        CallEndpointResolutionCode.unavailable,
        CallEndpointResolutionCode.blocked,
      ]) {
        fakeAsync((async) {
          final rig = _TerminalRetryRig(async);
          failInitial(rig, async);
          rig.endpointError = CallEndpointResolutionException(code);
          async.elapse(const Duration(seconds: 1));
          expect(rig.mailbox.requests, hasLength(1));
          rig.endpointError = null;
          rig.mailbox.online = true;
          async.elapse(const Duration(seconds: 2));
          expect(
            rig.mailbox.requests,
            hasLength(code == CallEndpointResolutionCode.unavailable ? 2 : 1),
          );
          expect(rig.service.pendingTerminalRetryCount, 0);
        });
      }
    },
  );

  test('terminal retry survives the production offline authority response', () {
    fakeAsync((async) {
      final rig = _TerminalRetryRig(async);
      final bridge = _RetryAuthorityBridge();
      final authority = BridgeCallAuthorityClient(bridge: bridge);
      failInitial(rig, async);
      final original = rig.mailbox.requests.single;
      rig.contexts.purge(_callId);
      rig.beforeEndpointLookup = () async {
        await authority.getEndpoint('remote-account');
      };
      bridge.errorCode = 'CALL_CONTROL_UNAVAILABLE';
      async.elapse(const Duration(milliseconds: 500));
      expect(bridge.lookups, 1);
      expect(rig.service.pendingTerminalRetryCount, 1);
      expect(rig.mailbox.requests, hasLength(1));

      bridge.errorCode = null;
      rig.mailbox.online = true;
      async.elapse(const Duration(seconds: 1));
      expect(bridge.lookups, 2);
      expect(rig.mailbox.requests, hasLength(2));
      final retry = rig.mailbox.requests.last;
      expect(retry.envelopeJson, original.envelopeJson);
      expect(retry.messageId, original.messageId);
      expect(retry.expiresAtMs, original.expiresAtMs);
      expect(rig.crypto.encryptions, 1);
      expect(rig.contexts.length, 0);
      expect(rig.service.pendingTerminalRetryCount, 0);
      rig.service.close();
    });
  });

  test('terminal retry rejects other production authority refusal codes', () {
    for (final code in [
      'CALL_UNAUTHORIZED',
      'CALL_STALE_EPOCH',
      'CALL_CONTROL_INVALID_RESPONSE',
      'CALL_CONTROL_UNSUPPORTED',
      'ARBITRARY_UNKNOWN_CODE',
    ]) {
      fakeAsync((async) {
        final rig = _TerminalRetryRig(async);
        final bridge = _RetryAuthorityBridge()..errorCode = code;
        final authority = BridgeCallAuthorityClient(bridge: bridge);
        failInitial(rig, async);
        rig.beforeEndpointLookup = () async {
          await authority.getEndpoint('remote-account');
        };
        async.elapse(const Duration(milliseconds: 500));
        expect(bridge.lookups, 1, reason: code);
        expect(rig.service.pendingTerminalRetryCount, 0, reason: code);
        bridge.errorCode = null;
        rig.mailbox.online = true;
        async.elapse(const Duration(seconds: 15));
        expect(rig.mailbox.requests, hasLength(1), reason: code);
        rig.service.close();
      });
    }
  });

  test('terminal retry disposal and expiry fence stalled authorization', () {
    for (final expire in [false, true]) {
      fakeAsync((async) {
        final rig = _TerminalRetryRig(async);
        failInitial(rig, async, lifetimeMs: expire ? 1000 : 40_000);
        final gate = Completer<void>();
        rig.endpointGate = gate.future;
        async.elapse(const Duration(milliseconds: 500));
        if (expire) {
          async.elapse(const Duration(milliseconds: 500));
        } else {
          rig.service.close();
        }
        expect(rig.service.pendingTerminalRetryCount, 0);
        rig.mailbox.online = true;
        gate.complete();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));
        expect(rig.mailbox.requests, hasLength(1));
      });
    }
  });

  test(
    'terminal retry capacity evicts oldest call without rebinding successors',
    () {
      fakeAsync((async) {
        final rig = _TerminalRetryRig(async);
        final ids = List.generate(
          5,
          (i) => CallId.parse('66666666-6666-4666-8666-66666666666$i'),
        );
        for (final id in ids) {
          failInitial(rig, async, callId: id);
        }
        expect(rig.service.pendingTerminalRetryCount, 4);
        rig.contexts.storeOutgoing(
          callId: _callId,
          callHandle: '77777777-7777-4777-8777-777777777777',
          localAccountPeerId: 'local-account',
          localDevicePeerId: 'local-device',
          remoteAccountPeerId: 'successor-account',
          remoteDevicePeerId: 'successor-device',
        );
        rig.mailbox.online = true;
        async.elapse(const Duration(seconds: 1));
        expect(rig.mailbox.requests, hasLength(9));
        expect(rig.service.pendingTerminalRetryCount, 0);
        final retried = rig.mailbox.requests
            .skip(5)
            .map((r) => r.envelopeJson)
            .toSet();
        expect(
          retried,
          isNot(contains(rig.mailbox.requests.first.envelopeJson)),
        );
        expect(
          rig.contexts.read(_callId)?.remoteAccountPeerId,
          'successor-account',
        );
        expect(rig.contexts.length, 1);
      });
    },
  );

  test(
    'quiescing cancels old retries while allowing one fresh terminal attempt',
    () {
      fakeAsync((async) {
        final rig = _TerminalRetryRig(async);
        failInitial(rig, async);
        expect(rig.service.pendingTerminalRetryCount, 1);
        rig.service.stopRetries();
        expect(rig.service.pendingTerminalRetryCount, 0);
        failInitial(
          rig,
          async,
          callId: CallId.parse('77777777-7777-4777-8777-777777777777'),
        );
        expect(rig.mailbox.requests, hasLength(2));
        expect(rig.service.pendingTerminalRetryCount, 0);
        rig.mailbox.online = true;
        async.elapse(const Duration(seconds: 20));
        expect(rig.mailbox.requests, hasLength(2));
        rig.service.close();
      });
    },
  );

  test('failed nonterminal invite cannot enter terminal retry queue', () {
    fakeAsync((async) {
      final rig = _TerminalRetryRig(async);
      failInitial(rig, async, event: CallSignalType.invite);
      rig.mailbox.online = true;
      async.elapse(const Duration(seconds: 20));
      expect(rig.mailbox.requests, hasLength(1));
      expect(rig.service.pendingTerminalRetryCount, 0);
    });
  });

  test(
    'offline cancel cleanup finishes before retry and cannot affect successor',
    () {
      fakeAsync((async) {
        final rig = _TerminalRetryRig(async);
        rig.mailbox.online = true;
        final successor = CallId.parse('77777777-7777-4777-8777-777777777777');
        var callIds = 0;
        var messageIds = 0;
        late final CallControlEffectExecutor control;
        final coordinator = CallCoordinator(
          reducer: const CallReducer(),
          cleanupCoordinator: CallCleanupCoordinator([
            CallCleanupStep('call_signaling_context', (snapshot) async {
              await control.retireOutgoingPreconnectInvite(snapshot);
              rig.contexts.purge(snapshot.callId!);
            }, requiredForTerminalAck: true),
          ]),
          historyProjector: CallHistoryProjector(_History()),
          effectExecutor: control = CallControlEffectExecutor(
            contextStore: rig.contexts,
            signalingPort: rig.adapter,
            clock: () =>
                DateTime.fromMillisecondsSinceEpoch(rig.nowMs, isUtc: true),
            idSource: () => CallId.parse(
              '88888888-8888-4888-8888-88888888888${messageIds++}',
            ),
          ),
          clock: () =>
              DateTime.fromMillisecondsSinceEpoch(rig.nowMs, isUtc: true),
          idSource: () => callIds++ == 0 ? _callId : successor,
        );
        coordinator.placeCall(
          contactPeerId: 'remote-account',
          localAccountPeerId: 'local-account',
          localDeviceId: 'local-device',
        );
        async.flushMicrotasks();
        coordinator.dispatch(
          CallEvent(
            type: CallEventType.remoteRinging,
            eventId: 'ringing',
            occurredAt: DateTime.fromMillisecondsSinceEpoch(
              rig.nowMs,
              isUtc: true,
            ),
            callId: _callId,
            contactPeerId: 'remote-account',
          ),
        );
        async.flushMicrotasks();
        expect(coordinator.activeSession?.state, CallState.ringing);
        rig.mailbox.online = false;
        var cancelFinished = false;
        coordinator
            .dispatch(
              CallEvent(
                type: CallEventType.cancel,
                eventId: 'cancel-offline',
                occurredAt: DateTime.fromMillisecondsSinceEpoch(
                  rig.nowMs,
                  isUtc: true,
                ),
                callId: _callId,
                contactPeerId: 'remote-account',
              ),
            )
            .then((_) {
              cancelFinished = true;
            });
        async.flushMicrotasks();
        expect(cancelFinished, isTrue);
        expect(coordinator.terminalCleanupAckReady(_callId), isTrue);
        expect(rig.contexts.read(_callId), isNull);
        expect(rig.service.pendingTerminalRetryCount, 1);
        final cancelledEnvelope = rig.mailbox.requests.last.envelopeJson;
        rig.mailbox.online = true;
        coordinator.placeCall(
          contactPeerId: 'remote-account',
          localAccountPeerId: 'local-account',
          localDeviceId: 'local-device',
        );
        async.flushMicrotasks();
        expect(coordinator.activeSession?.callId, successor);
        final successorContext = rig.contexts.read(successor);
        async.elapse(const Duration(seconds: 1));
        expect(rig.mailbox.requests.last.envelopeJson, cancelledEnvelope);
        expect(coordinator.activeSession?.callId, successor);
        expect(coordinator.activeSession?.state, CallState.inviting);
        expect(
          rig.contexts.read(successor)?.callHandle,
          successorContext?.callHandle,
        );
        expect(rig.contexts.read(_callId), isNull);
        expect(rig.service.pendingTerminalRetryCount, 0);
        rig.mailbox.online = false;
        final beforeShutdown = rig.mailbox.requests.length;
        rig.service.stopRetries();
        coordinator.dispose();
        async.flushMicrotasks();
        rig.service.close();
        expect(
          rig.mailbox.requests.length,
          beforeShutdown + 1,
          reason: 'active appShutdown keeps its one normal terminal attempt',
        );
        expect(rig.service.pendingTerminalRetryCount, 0);
      });
    },
  );

  test(
    'durable diagnostics keep direct success distinct from failed mailbox custody',
    () async {
      final diagnostics = await CallDiagnostics.installForTesting();
      addTearDown(() async {
        await diagnostics.setEnabled(false);
        await diagnostics.dispose();
      });
      final coordinator = _coordinator();
      addTearDown(coordinator.dispose);
      await _prepare(coordinator);
      final trace = diagnostics.beginAttempt()!;
      const handle = '33333333-3333-4333-8333-333333333333';
      diagnostics.bindCall(
        callId: _callId.value,
        callHandle: handle,
        traceId: trace,
      );
      final service = CallSignalingService(
        codec: SecureCallEnvelopeCodec(crypto: _Crypto(), nowMs: () => _nowMs),
        directTransport: _Direct(
          const CallDirectSendResult(
            outcome: CallDirectTransportOutcome.acceptedBytes,
            transportAcknowledged: true,
            route: CallDirectRoute.direct,
          ),
        ),
        mailboxClient: _Mailbox(storeSucceeds: false, leakFailureDetails: true),
        coordinator: coordinator,
        networkEffectsAllowed: () => true,
      );
      final result = await service.send(
        signal: _invite(),
        callHandle: handle,
        endpoint: _endpoint,
        senderSigningPrivateKey: 'local-signing',
      );
      await result.mailboxStoreSettled;
      expect(result.directAccepted, isTrue);
      expect(coordinator.activeSession!.mailboxCustodyConfirmed, isFalse);
      final events = await diagnostics.eventsForTesting();
      expect(
        events.any(
          (event) =>
              event['traceId'] == trace &&
              event['action'] == 'send_direct' &&
              event['outcome'] == 'ok',
        ),
        isTrue,
      );
      expect(
        events.any(
          (event) =>
              event['traceId'] == trace &&
              event['action'] == 'commit' &&
              event['outcome'] == 'failed' &&
              (event['values'] as Map)['storeCommitted'] == false,
        ),
        isTrue,
      );
      expect(jsonEncode(events), isNot(contains('secret-token')));
      expect(jsonEncode(events), isNot(contains(handle)));
    },
  );

  test(
    'direct acceptance exposes exact mailbox settlement before retirement',
    () {
      fakeAsync((clock) {
        final coordinator = _coordinator();
        var prepared = false;
        unawaited(_prepare(coordinator).then<void>((_) => prepared = true));
        clock.flushMicrotasks();
        expect(prepared, isTrue);

        final direct = _CompleterDirect();
        final mailbox = _CompleterMailbox();
        final service = CallSignalingService(
          codec: SecureCallEnvelopeCodec(
            crypto: _Crypto(),
            nowMs: () => _nowMs,
          ),
          directTransport: direct,
          mailboxClient: mailbox,
          coordinator: coordinator,
          networkEffectsAllowed: () => true,
        );
        CallSignalTransportResult? result;
        Object? failure;
        unawaited(
          service
              .send(
                signal: _invite(),
                callHandle: '33333333-3333-4333-8333-333333333333',
                endpoint: _endpoint,
                senderSigningPrivateKey: 'local-signing',
              )
              .then<void>(
                (value) => result = value,
                onError: (Object error, StackTrace stackTrace) {
                  failure = error;
                },
              ),
        );
        clock.flushMicrotasks();
        expect(direct.calls, 1);
        expect(mailbox.stores, 1);
        expect(result, isNull);

        clock.elapse(const Duration(milliseconds: 250));
        direct.result.complete(
          const CallDirectSendResult(
            outcome: CallDirectTransportOutcome.acceptedBytes,
            transportAcknowledged: true,
            route: CallDirectRoute.direct,
          ),
        );
        clock.flushMicrotasks();

        expect(failure, isNull);
        expect(result?.directAccepted, isTrue);
        expect(result?.mailboxStored, isFalse);
        expect(result?.directRoute, CallDirectRoute.direct);
        expect(clock.elapsed, const Duration(milliseconds: 250));
        expect(mailbox.result.isCompleted, isFalse);

        final returned = result!;
        Object? retirementFailure;
        var retirementCompleted = false;
        unawaited(
          returned.mailboxStoreSettled.then<void>(
            (_) async {
              await mailbox.cancel(
                recipientDevicePeerId: _endpoint.devicePeerId,
                callHandle: '33333333-3333-4333-8333-333333333333',
              );
              retirementCompleted = true;
            },
            onError: (Object error, StackTrace stackTrace) {
              retirementFailure = error;
            },
          ),
        );
        clock.flushMicrotasks();
        expect(retirementCompleted, isFalse);
        expect(mailbox.cancels, 0);

        mailbox.completeStore();
        clock.flushMicrotasks();

        expect(retirementFailure, isNull);
        expect(retirementCompleted, isTrue);
        expect(mailbox.cancels, 1);
        expect(mailbox.operations, <String>['store-settled', 'cancel']);
        expect(returned.directAccepted, isTrue);
        expect(returned.mailboxStored, isFalse);
        expect(returned.directRoute, CallDirectRoute.direct);
        expect(direct.calls, 1);
        expect(mailbox.stores, 1);

        var disposed = false;
        unawaited(coordinator.dispose().then<void>((_) => disposed = true));
        clock.flushMicrotasks();
        expect(disposed, isTrue);
      });
    },
  );

  test(
    'mailbox custody returns in the same virtual turn while direct is hung',
    () {
      fakeAsync((clock) {
        final coordinator = _coordinator();
        var prepared = false;
        unawaited(_prepare(coordinator).then<void>((_) => prepared = true));
        clock.flushMicrotasks();
        expect(prepared, isTrue);

        final direct = _CompleterDirect();
        final mailbox = _CompleterMailbox();
        final service = CallSignalingService(
          codec: SecureCallEnvelopeCodec(
            crypto: _Crypto(),
            nowMs: () => _nowMs,
          ),
          directTransport: direct,
          mailboxClient: mailbox,
          coordinator: coordinator,
          networkEffectsAllowed: () => true,
        );
        CallSignalTransportResult? result;
        Object? failure;
        unawaited(
          service
              .send(
                signal: _invite(),
                callHandle: '33333333-3333-4333-8333-333333333333',
                endpoint: _endpoint,
                senderSigningPrivateKey: 'local-signing',
              )
              .then<void>(
                (value) => result = value,
                onError: (Object error, StackTrace stackTrace) {
                  failure = error;
                },
              ),
        );
        clock.flushMicrotasks();
        expect(direct.calls, 1);
        expect(mailbox.stores, 1);
        expect(result, isNull);

        clock.elapse(const Duration(milliseconds: 250));
        mailbox.result.complete(
          const CallMailboxStoreResult(
            status: CallMailboxStoreStatus.stored,
            receiptAtMs: _nowMs,
            expiresAtMs: _nowMs + 45_000,
            eventCount: 1,
            totalBytes: 100,
            pendingHandles: 1,
          ),
        );
        clock.flushMicrotasks();

        expect(failure, isNull);
        expect(result?.directAccepted, isFalse);
        expect(result?.mailboxStored, isTrue);
        expect(result?.directRoute, CallDirectRoute.unknown);
        expect(clock.elapsed, const Duration(milliseconds: 250));
        expect(direct.result.isCompleted, isFalse);
        expect(coordinator.activeSession?.mailboxCustodyConfirmed, isTrue);
        expect(
          coordinator.activeSession?.recentEventIds,
          contains('11111111-1111-4111-8111-111111111111:mailbox-stored'),
        );
        expect(
          coordinator.activeSession?.recentEventIds,
          isNot(contains('11111111-1111-4111-8111-111111111111:direct-failed')),
        );

        direct.result.complete(
          const CallDirectSendResult(
            outcome: CallDirectTransportOutcome.failed,
            transportAcknowledged: false,
            route: CallDirectRoute.unknown,
          ),
        );
        clock.flushMicrotasks();
        expect(direct.calls, 1);
        expect(mailbox.stores, 1);
        expect(
          coordinator.activeSession?.recentEventIds,
          isNot(contains('11111111-1111-4111-8111-111111111111:direct-failed')),
        );

        var disposed = false;
        unawaited(coordinator.dispose().then<void>((_) => disposed = true));
        clock.flushMicrotasks();
        expect(disposed, isTrue);
      });
    },
  );

  test('a wake receipt confirms custody without recipient alerting', () {
    fakeAsync((clock) {
      final coordinator = _coordinator();
      var prepared = false;
      unawaited(_prepare(coordinator).then<void>((_) => prepared = true));
      clock.flushMicrotasks();
      expect(prepared, isTrue);

      final direct = _CompleterDirect();
      final mailbox = _CompleterMailbox();
      final service = CallSignalingService(
        codec: SecureCallEnvelopeCodec(crypto: _Crypto(), nowMs: () => _nowMs),
        directTransport: direct,
        mailboxClient: mailbox,
        coordinator: coordinator,
        networkEffectsAllowed: () => true,
      );
      CallSignalTransportResult? result;
      Object? failure;
      unawaited(
        service
            .send(
              signal: _invite(),
              callHandle: '33333333-3333-4333-8333-333333333333',
              endpoint: _endpoint,
              senderSigningPrivateKey: 'local-signing',
            )
            .then<void>(
              (value) => result = value,
              onError: (Object error, StackTrace stackTrace) {
                failure = error;
              },
            ),
      );
      clock.flushMicrotasks();
      expect(direct.calls, 1);
      expect(mailbox.stores, 1);
      expect(result, isNull);

      clock.elapse(const Duration(milliseconds: 250));
      mailbox.result.complete(
        const CallMailboxStoreResult(
          status: CallMailboxStoreStatus.stored,
          receiptAtMs: _nowMs,
          expiresAtMs: _nowMs + 45_000,
          eventCount: 1,
          totalBytes: 100,
          pendingHandles: 1,
          wake: CallMailboxWakeStatus.dispatched,
        ),
      );
      clock.flushMicrotasks();

      expect(failure, isNull);
      expect(result?.directAccepted, isFalse);
      expect(result?.mailboxStored, isTrue);
      expect(result?.directRoute, CallDirectRoute.unknown);
      expect(clock.elapsed, const Duration(milliseconds: 250));
      expect(direct.result.isCompleted, isFalse);
      expect(coordinator.activeSession?.mailboxCustodyConfirmed, isTrue);
      expect(coordinator.activeSession?.state, CallState.inviting);
      expect(coordinator.activeSession?.ringingAt, isNull);
      expect(
        coordinator.activeSession?.recentEventIds,
        contains('11111111-1111-4111-8111-111111111111:wake-dispatched'),
      );
      expect(
        coordinator.activeSession?.recentEventIds,
        contains('11111111-1111-4111-8111-111111111111:mailbox-stored'),
      );
      expect(
        coordinator.activeSession?.recentEventIds,
        isNot(contains('11111111-1111-4111-8111-111111111111:direct-failed')),
      );

      direct.result.complete(
        const CallDirectSendResult(
          outcome: CallDirectTransportOutcome.failed,
          transportAcknowledged: false,
          route: CallDirectRoute.unknown,
        ),
      );
      clock.flushMicrotasks();
      expect(direct.calls, 1);
      expect(mailbox.stores, 1);
      expect(
        coordinator.activeSession?.recentEventIds,
        isNot(contains('11111111-1111-4111-8111-111111111111:direct-failed')),
      );

      var disposed = false;
      unawaited(coordinator.dispose().then<void>((_) => disposed = true));
      clock.flushMicrotasks();
      expect(disposed, isTrue);
    });
  });

  test('mailbox settlement completes without error after store failure', () {
    fakeAsync((clock) {
      final coordinator = _coordinator();
      final direct = _CompleterDirect();
      final mailbox = _CompleterMailbox();
      final service = CallSignalingService(
        codec: SecureCallEnvelopeCodec(crypto: _Crypto(), nowMs: () => _nowMs),
        directTransport: direct,
        mailboxClient: mailbox,
        coordinator: coordinator,
        networkEffectsAllowed: () => true,
      );
      CallSignalTransportResult? result;
      unawaited(
        service
            .transmit(
              signal: _invite(),
              callHandle: '33333333-3333-4333-8333-333333333333',
              endpoint: _endpoint,
              senderSigningPrivateKey: 'local-signing',
            )
            .then<void>((value) => result = value),
      );
      clock.flushMicrotasks();
      direct.result.complete(
        const CallDirectSendResult(
          outcome: CallDirectTransportOutcome.acceptedBytes,
          transportAcknowledged: true,
          route: CallDirectRoute.direct,
        ),
      );
      clock.flushMicrotasks();

      final returned = result!;
      Object? settlementFailure;
      var settlementCompleted = false;
      unawaited(
        returned.mailboxStoreSettled.then<void>(
          (_) => settlementCompleted = true,
          onError: (Object error, StackTrace stackTrace) {
            settlementFailure = error;
          },
        ),
      );
      clock.flushMicrotasks();
      expect(settlementCompleted, isFalse);

      mailbox.failStore();
      clock.flushMicrotasks();

      expect(settlementFailure, isNull);
      expect(settlementCompleted, isTrue);
      expect(mailbox.operations, <String>['store-failed']);
      expect(returned.directAccepted, isTrue);
      expect(returned.mailboxStored, isFalse);
      expect(returned.directRoute, CallDirectRoute.direct);

      var disposed = false;
      unawaited(coordinator.dispose().then<void>((_) => disposed = true));
      clock.flushMicrotasks();
      expect(disposed, isTrue);
    });
  });

  test(
    'direct failure still gains call-mailbox custody without false ringing',
    () async {
      final coordinator = _coordinator();
      addTearDown(coordinator.dispose);
      await _prepare(coordinator);
      final direct = _Direct(
        const CallDirectSendResult(
          outcome: CallDirectTransportOutcome.failed,
          transportAcknowledged: false,
          route: CallDirectRoute.unknown,
        ),
      );
      final mailbox = _Mailbox(storeSucceeds: true);
      final service = CallSignalingService(
        codec: SecureCallEnvelopeCodec(crypto: _Crypto(), nowMs: () => _nowMs),
        directTransport: direct,
        mailboxClient: mailbox,
        coordinator: coordinator,
        networkEffectsAllowed: () => true,
      );
      final result = await service.send(
        signal: _invite(),
        callHandle: '33333333-3333-4333-8333-333333333333',
        endpoint: _endpoint,
        senderSigningPrivateKey: 'local-signing',
      );

      expect(result.directAccepted, isFalse);
      expect(result.mailboxStored, isTrue);
      expect(direct.envelope, mailbox.request?.envelopeJson);
      expect(mailbox.request?.wakeHandle, _endpoint.wakeHandle);
      expect(mailbox.request?.wakeHandle, isNot(_endpoint.routingHandle));
      expect(coordinator.activeSession?.mailboxCustodyConfirmed, isTrue);
      expect(coordinator.activeSession?.state, CallState.inviting);
    },
  );

  test('direct exception cannot erase committed mailbox custody', () async {
    final coordinator = _coordinator();
    addTearDown(coordinator.dispose);
    await _prepare(coordinator);
    final direct = _ThrowingDirect();
    final mailbox = _Mailbox(storeSucceeds: true);
    final service = CallSignalingService(
      codec: SecureCallEnvelopeCodec(crypto: _Crypto(), nowMs: () => _nowMs),
      directTransport: direct,
      mailboxClient: mailbox,
      coordinator: coordinator,
      networkEffectsAllowed: () => true,
    );

    final result = await service.send(
      signal: _invite(),
      callHandle: '33333333-3333-4333-8333-333333333333',
      endpoint: _endpoint,
      senderSigningPrivateKey: 'local-signing',
    );

    expect(direct.calls, 1);
    expect(result.directAccepted, isFalse);
    expect(result.mailboxStored, isTrue);
    expect(coordinator.activeSession?.mailboxCustodyConfirmed, isTrue);
    expect(coordinator.activeSession?.state, CallState.inviting);
  });

  test(
    'leg diagnostics distinguish failures and exclude signaling material',
    () async {
      final diagnostics = <Map<String, dynamic>>[];
      debugSetFlowEventSink(diagnostics.add);
      addTearDown(() => debugSetFlowEventSink(null));
      final coordinator = _coordinator();
      addTearDown(coordinator.dispose);
      await _prepare(coordinator);
      final mailbox = _Mailbox(storeSucceeds: false, leakFailureDetails: true);
      final service = CallSignalingService(
        codec: SecureCallEnvelopeCodec(crypto: _Crypto(), nowMs: () => _nowMs),
        directTransport: _ThrowingDirect(leakFailureDetails: true),
        mailboxClient: mailbox,
        coordinator: coordinator,
        networkEffectsAllowed: () => true,
      );

      await expectLater(
        service.transmit(
          signal: _invite(),
          callHandle: '33333333-3333-4333-8333-333333333333',
          endpoint: _endpoint,
          senderSigningPrivateKey: 'local-signing',
        ),
        throwsA(
          isA<CallSignalingException>().having(
            (error) => error.code,
            'code',
            CallSignalingErrorCode.transportUnavailable,
          ),
        ),
      );

      final legResults =
          diagnostics
              .where((event) => event['event'] == 'CALL_SIGNALING_LEG_RESULT')
              .map((event) => event['details'] as Map<String, dynamic>)
              .toList(growable: false)
            ..sort(
              (left, right) => (left['operation'] as String).compareTo(
                right['operation'] as String,
              ),
            );
      expect(legResults, <Object?>[
        <String, Object?>{'operation': 'direct_send', 'result': false},
        <String, Object?>{'operation': 'mailbox_store', 'result': false},
      ]);

      final diagnosticText = jsonEncode(legResults);
      for (final forbidden in <String>[
        _callId.value,
        'local-account',
        'local-device',
        'remote-account',
        'remote-device',
        '11111111-1111-4111-8111-111111111111',
        '33333333-3333-4333-8333-333333333333',
        _routingHandle,
        _wakeHandle,
        'local-signing',
        'secret-token',
        'raw-error',
        '/ip4/203.0.113.8/tcp/4001/p2p/relay-peer',
        '$_nowMs',
        '${_nowMs + 45_000}',
        mailbox.request!.envelopeJson,
      ]) {
        expect(diagnosticText, isNot(contains(forbidden)));
      }
    },
  );

  test('diagnostic sink failure cannot change either leg result', () async {
    debugSetFlowEventSink((_) => throw StateError('diagnostic sink failed'));
    addTearDown(() => debugSetFlowEventSink(null));
    final coordinator = _coordinator();
    addTearDown(coordinator.dispose);
    await _prepare(coordinator);
    final service = CallSignalingService(
      codec: SecureCallEnvelopeCodec(crypto: _Crypto(), nowMs: () => _nowMs),
      directTransport: _Direct(
        const CallDirectSendResult(
          outcome: CallDirectTransportOutcome.acceptedBytes,
          transportAcknowledged: true,
          route: CallDirectRoute.direct,
        ),
      ),
      mailboxClient: _Mailbox(storeSucceeds: true),
      coordinator: coordinator,
      networkEffectsAllowed: () => true,
    );

    final result = await service.transmit(
      signal: _invite(),
      callHandle: '33333333-3333-4333-8333-333333333333',
      endpoint: _endpoint,
      senderSigningPrivateKey: 'local-signing',
    );

    expect(result.directAccepted, isTrue);
    expect(result.mailboxStored, isTrue);
  });

  test(
    'transport ACK records bytes only and cannot synthesize ringing',
    () async {
      final coordinator = _coordinator();
      addTearDown(coordinator.dispose);
      await _prepare(coordinator);
      final service = CallSignalingService(
        codec: SecureCallEnvelopeCodec(crypto: _Crypto(), nowMs: () => _nowMs),
        directTransport: _Direct(
          const CallDirectSendResult(
            outcome: CallDirectTransportOutcome.acceptedBytes,
            transportAcknowledged: true,
            route: CallDirectRoute.direct,
          ),
        ),
        mailboxClient: _Mailbox(storeSucceeds: true),
        coordinator: coordinator,
        networkEffectsAllowed: () => true,
      );

      final result = await service.send(
        signal: _invite(),
        callHandle: '33333333-3333-4333-8333-333333333333',
        endpoint: _endpoint,
        senderSigningPrivateKey: 'local-signing',
      );

      expect(result.directAccepted, isTrue);
      expect(coordinator.activeSession?.state, CallState.inviting);
      expect(coordinator.activeSession?.ringingAt, isNull);
    },
  );

  test(
    'network-only transmit returns receipts without recursively dispatching',
    () async {
      final coordinator = _coordinator();
      addTearDown(coordinator.dispose);
      await _prepare(coordinator);
      final service = CallSignalingService(
        codec: SecureCallEnvelopeCodec(crypto: _Crypto(), nowMs: () => _nowMs),
        directTransport: _Direct(
          const CallDirectSendResult(
            outcome: CallDirectTransportOutcome.acceptedBytes,
            transportAcknowledged: true,
            route: CallDirectRoute.direct,
          ),
        ),
        mailboxClient: _Mailbox(storeSucceeds: true),
        coordinator: coordinator,
        networkEffectsAllowed: () => true,
      );
      final eventsBeforeTransmit = List<String>.of(
        coordinator.activeSession!.recentEventIds,
      );

      final result = await service.transmit(
        signal: _invite(),
        callHandle: '33333333-3333-4333-8333-333333333333',
        endpoint: _endpoint,
        senderSigningPrivateKey: 'local-signing',
      );

      expect(result.directAccepted, isTrue);
      expect(result.mailboxStored, isTrue);
      expect(coordinator.activeSession?.mailboxCustodyConfirmed, isFalse);
      expect(coordinator.activeSession?.recentEventIds, eventsBeforeTransmit);
      expect(coordinator.activeSession?.state, CallState.inviting);
    },
  );

  test('migration pause fails before codec or either transport', () async {
    final coordinator = _coordinator();
    addTearDown(coordinator.dispose);
    final direct = _Direct(
      const CallDirectSendResult(
        outcome: CallDirectTransportOutcome.acceptedBytes,
        transportAcknowledged: true,
        route: CallDirectRoute.direct,
      ),
    );
    final mailbox = _Mailbox(storeSucceeds: true);
    final service = CallSignalingService(
      codec: SecureCallEnvelopeCodec(crypto: _Crypto(), nowMs: () => _nowMs),
      directTransport: direct,
      mailboxClient: mailbox,
      coordinator: coordinator,
      networkEffectsAllowed: () => false,
    );

    await expectLater(
      service.send(
        signal: _invite(),
        callHandle: '33333333-3333-4333-8333-333333333333',
        endpoint: _endpoint,
        senderSigningPrivateKey: 'local-signing',
      ),
      throwsA(
        isA<CallSignalingException>().having(
          (error) => error.code,
          'code',
          CallSignalingErrorCode.migrationPaused,
        ),
      ),
    );
    expect(direct.calls, 0);
    expect(mailbox.stores, 0);
  });

  test(
    'malformed received wake handle fails before either transport',
    () async {
      final coordinator = _coordinator();
      addTearDown(coordinator.dispose);
      final direct = _Direct(
        const CallDirectSendResult(
          outcome: CallDirectTransportOutcome.acceptedBytes,
          transportAcknowledged: true,
          route: CallDirectRoute.direct,
        ),
      );
      final mailbox = _Mailbox(storeSucceeds: true);
      final service = CallSignalingService(
        codec: SecureCallEnvelopeCodec(crypto: _Crypto(), nowMs: () => _nowMs),
        directTransport: direct,
        mailboxClient: mailbox,
        coordinator: coordinator,
        networkEffectsAllowed: () => true,
      );
      const malformedEndpoint = ResolvedCallEndpoint(
        accountPeerId: 'remote-account',
        devicePeerId: 'remote-device',
        signingPublicKey: 'remote-signing',
        mlKemPublicKey: 'remote-mlkem',
        deviceKeyEpoch: 1,
        preferenceEpoch: 1,
        platform: CallEndpointPlatform.android,
        expiresAtMs: _nowMs + 60_000,
        routingHandle: _routingHandle,
        wakeHandle: 'not-a-wake-handle',
      );

      await expectLater(
        service.transmit(
          signal: _invite(),
          callHandle: '33333333-3333-4333-8333-333333333333',
          endpoint: malformedEndpoint,
          senderSigningPrivateKey: 'local-signing',
        ),
        throwsA(
          isA<CallSignalingException>().having(
            (error) => error.code,
            'code',
            CallSignalingErrorCode.endpointMismatch,
          ),
        ),
      );
      expect(direct.calls, 0);
      expect(mailbox.stores, 0);
    },
  );

  // Plan 404: the headless decline reply runs without a coordinator lane; the
  // transport legs must stay usable on their own.
  test(
    'transmit needs no coordinator and send fails closed without one',
    () async {
      final direct = _Direct(
        const CallDirectSendResult(
          outcome: CallDirectTransportOutcome.acceptedBytes,
          transportAcknowledged: true,
          route: CallDirectRoute.circuitRelay,
        ),
      );
      final mailbox = _Mailbox(storeSucceeds: true);
      final service = CallSignalingService(
        codec: SecureCallEnvelopeCodec(crypto: _Crypto(), nowMs: () => _nowMs),
        directTransport: direct,
        mailboxClient: mailbox,
        networkEffectsAllowed: () => true,
      );
      final signal = CallSignal.create(
        callId: CallId.parse('22222222-2222-4222-8222-222222222222'),
        messageId: '55555555-5555-4555-8555-555555555555',
        event: CallSignalType.reject,
        senderAccountPeerId: 'local-account',
        senderDevicePeerId: 'local-device',
        recipientAccountPeerId: 'caller-account',
        recipientDevicePeerId: 'caller-device',
        senderSequence: 1,
        iceGeneration: 0,
        createdAtMs: _nowMs,
        expiresAtMs: _nowMs + 40_000,
        payload: const <String, Object?>{'reason': 'declined'},
      );
      final endpoint = ResolvedCallEndpoint(
        accountPeerId: 'caller-account',
        devicePeerId: 'caller-device',
        signingPublicKey: 'caller-signing-key',
        mlKemPublicKey: 'caller-kem-key',
        deviceKeyEpoch: 1,
        preferenceEpoch: 1,
        platform: CallEndpointPlatform.ios,
        expiresAtMs: _nowMs + 60_000,
        routingHandle: 'caller-routing-handle',
        wakeHandle: 'a' * 32,
      );

      final transport = await service.transmit(
        signal: signal,
        callHandle: '22222222-2222-4222-8222-222222222222',
        endpoint: endpoint,
        senderSigningPrivateKey: 'local-signing-key',
      );
      expect(transport.delivered, isTrue);
      expect(direct.calls, 1);
      expect(mailbox.stores, 1);

      await expectLater(
        service.send(
          signal: signal,
          callHandle: '22222222-2222-4222-8222-222222222222',
          endpoint: endpoint,
          senderSigningPrivateKey: 'local-signing-key',
        ),
        throwsStateError,
      );
    },
  );

  test(
    'call signaling production roots exclude ordinary notification and retrier seams',
    () {
      const paths = <String>[
        'lib/features/call/application/call_signaling_service.dart',
        'lib/features/call/application/handle_incoming_call_signal.dart',
        'lib/features/call/infrastructure/call_signaling_runtime.dart',
        'lib/features/call/infrastructure/call_mailbox_client.dart',
        'lib/features/call/infrastructure/p2p_call_transport.dart',
      ];
      const forbidden = <String>[
        'core/services/pending_message_retrier.dart',
        'core/notifications/',
        'features/conversation/',
        'PendingMessageRetrier(',
        '.storeInInbox(',
      ];

      for (final path in paths) {
        final source = File(path).readAsStringSync();
        for (final token in forbidden) {
          expect(source, isNot(contains(token)), reason: '$path: $token');
        }
      }
    },
  );
}

final class _TerminalRetryMailbox implements CallMailboxClient {
  bool online = false;
  final requests = <CallMailboxStoreRequest>[];

  @override
  Future<CallMailboxStoreResult> store(CallMailboxStoreRequest request) async {
    requests.add(request);
    if (!online) throw StateError('offline');
    return CallMailboxStoreResult(
      status: CallMailboxStoreStatus.stored,
      receiptAtMs: _nowMs,
      expiresAtMs: request.expiresAtMs,
      eventCount: 1,
      totalBytes: request.envelopeJson.length,
      pendingHandles: 1,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _TerminalRetryRig {
  _TerminalRetryRig(this.async) {
    service = CallSignalingService(
      codec: SecureCallEnvelopeCodec(crypto: crypto, nowMs: () => nowMs),
      nowMs: () => nowMs,
      retryJitter: () => 0.5,
      directTransport: direct,
      mailboxClient: mailbox,
      networkEffectsAllowed: () => networkAllowed,
    );
    adapter = ProductionCallControlSignalingAdapter(
      signalingService: service,
      contextStore: contexts,
      resolveCurrentEndpoint: (_) async {
        await endpointGate;
        await beforeEndpointLookup?.call();
        if (endpointError != null) throw endpointError!;
        return endpoint;
      },
      loadSenderSigningPrivateKey: () async {
        await keyGate;
        if (!accountCurrent) throw StateError('identity changed');
        return 'local-signing';
      },
      clock: () => DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true),
    );
  }

  final FakeAsync async;
  final contexts = CallSignalingContextStore();
  final mailbox = _TerminalRetryMailbox();
  final crypto = _TerminalRetryCrypto();
  final direct = _ThrowingDirect();
  late final CallSignalingService service;
  late final ProductionCallControlSignalingAdapter adapter;
  bool networkAllowed = true;
  bool accountCurrent = true;
  ResolvedCallEndpoint endpoint = _endpoint;
  Future<void>? endpointGate;
  Future<void> Function()? beforeEndpointLookup;
  Future<void>? keyGate;
  Object? endpointError;
  int get nowMs => _nowMs + async.elapsed.inMilliseconds;

  Future<void> send({
    CallSignalType event = CallSignalType.terminate,
    CallId? callId,
    int lifetimeMs = 40_000,
  }) async {
    await adapter.send(
      signal: CallSignal.create(
        callId: callId ?? _callId,
        messageId: '55555555-5555-4555-8555-555555555555',
        event: event,
        senderAccountPeerId: 'local-account',
        senderDevicePeerId: 'local-device',
        recipientAccountPeerId: 'remote-account',
        recipientDevicePeerId: 'remote-device',
        senderSequence: 2,
        iceGeneration: 0,
        createdAtMs: _nowMs,
        expiresAtMs: _nowMs + lifetimeMs,
        payload: event == CallSignalType.invite
            ? const <String, Object?>{}
            : const <String, Object?>{'reason': 'caller_cancelled'},
      ),
      callHandle: '33333333-3333-4333-8333-333333333333',
    );
  }
}

final class _RetryAuthorityBridge implements Bridge {
  String? errorCode;
  int lookups = 0;

  @override
  Future<String> send(String message) async {
    expect(jsonDecode(message)['cmd'], 'call_endpoint_get_v1');
    lookups++;
    return jsonEncode(
      errorCode == null
          ? <String, Object?>{'ok': true, 'found': false}
          : <String, Object?>{'ok': false, 'errorCode': errorCode},
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _TerminalRetryCrypto implements CallEnvelopeCrypto {
  int encryptions = 0;

  @override
  Future<CallCiphertext> encrypt({
    required String recipientMlKemPublicKey,
    required String plaintext,
  }) async {
    final encrypted = await _Crypto().encrypt(
      recipientMlKemPublicKey: recipientMlKemPublicKey,
      plaintext: plaintext,
    );
    return CallCiphertext(
      kem: encrypted.kem,
      ciphertext: encrypted.ciphertext,
      nonce: base64Encode(utf8.encode('nonce-${++encryptions}')),
    );
  }

  @override
  Future<String> sign({
    required String senderSigningPrivateKey,
    required String canonicalData,
  }) => _Crypto().sign(
    senderSigningPrivateKey: senderSigningPrivateKey,
    canonicalData: canonicalData,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
