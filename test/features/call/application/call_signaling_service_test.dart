import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/call_signaling_service.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_app/features/call/infrastructure/call_mailbox_client.dart';
import 'package:flutter_app/features/call/infrastructure/p2p_call_transport.dart';
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
