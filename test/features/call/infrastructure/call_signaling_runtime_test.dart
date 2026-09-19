import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/handle_incoming_call_signal.dart';
import 'package:flutter_app/features/call/application/call_signaling_context_store.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/call/domain/issued_call_wake_handle_store.dart';
import 'package:flutter_app/features/call/infrastructure/android_call_admission_settlement.dart';
import 'package:flutter_app/features/call/infrastructure/call_mailbox_client.dart';
import 'package:flutter_app/features/call/infrastructure/call_signaling_runtime.dart';
import 'package:flutter_app/features/call/infrastructure/call_trusted_roster_provider.dart';
import 'package:flutter_app/features/call/infrastructure/secure_call_envelope_codec.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

final class _History implements CallHistoryRepository {
  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async => null;

  @override
  Future<List<CallHistoryEntry>> listForContact(String peerId) async =>
      const [];

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {}
}

final class _ThrowingRuntimeHistory implements CallHistoryRepository {
  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async => null;

  @override
  Future<List<CallHistoryEntry>> listForContact(String peerId) async =>
      const <CallHistoryEntry>[];

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {
    throw StateError('history unavailable');
  }
}

CallCoordinator _coordinator({
  CallEffectExecutor effects = const NoopCallEffectExecutor(),
}) => CallCoordinator(
  reducer: const CallReducer(),
  cleanupCoordinator: CallCleanupCoordinator(const <CallCleanupStep>[]),
  historyProjector: CallHistoryProjector(_History()),
  effectExecutor: effects,
  clock: () => DateTime.utc(2026, 8, 30),
  idSource: () => CallId.parse('11111111-1111-4111-8111-111111111111'),
);

final class _PendingMediaEffects implements CallEffectExecutor {
  final preparing = Completer<void>();
  final release = Completer<void>();

  @override
  Future<CallEvent?> execute(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) async {
    if (effect.type == CallEffectType.startNegotiation) {
      preparing.complete();
      await release.future;
      return CallEvent(
        type: CallEventType.negotiationReady,
        eventId: 'late-negotiation',
        occurredAt: _runtimeNow,
        callId: snapshot.callId,
        contactPeerId: snapshot.contactPeerId,
      );
    }
    return null;
  }
}

final class _Mailbox implements CallMailboxClient {
  final List<CallMailboxRetrieveResult> pages = <CallMailboxRetrieveResult>[];
  int retrieves = 0;
  int acks = 0;
  int ackAttempts = 0;
  bool failAcks = false;
  int? ackResult;
  Future<void>? ackBarrier;
  final ackEntered = Completer<void>();
  Future<void>? retrieveBarrier;

  @override
  Future<CallMailboxRetrieveResult> retrieve({
    String? callHandle,
    int limit = 64,
  }) async {
    retrieves++;
    await retrieveBarrier;
    if (pages.isNotEmpty) return pages.removeAt(0);
    return CallMailboxRetrieveResult(
      events: <CallMailboxEvent>[],
      receiptAtMs: 0,
      expiresAtMs: 0,
      hasMore: false,
    );
  }

  @override
  Future<int> ack({
    required String callHandle,
    required List<String> messageIds,
  }) async {
    ackAttempts++;
    if (!ackEntered.isCompleted) ackEntered.complete();
    await ackBarrier;
    if (failAcks) throw StateError('temporary mailbox failure');
    final count = ackResult ?? messageIds.length;
    acks += count;
    return count;
  }

  @override
  Future<bool> cancel({
    required String recipientDevicePeerId,
    required String callHandle,
  }) => throw UnimplementedError();

  @override
  Future<CallMailboxStoreResult> store(CallMailboxStoreRequest request) =>
      throw UnimplementedError();
}

final _runtimeNow = DateTime.utc(2026, 8, 30);
final _runtimeNowMs = _runtimeNow.millisecondsSinceEpoch;

final class _RuntimeCrypto implements CallEnvelopeCrypto {
  bool throwOnVerify = false;
  bool throwOnDecrypt = false;
  final List<String?> decryptOverrides = <String?>[];

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
  }) async {
    if (throwOnDecrypt) throw StateError('crypto bridge unavailable');
    if (decryptOverrides.isNotEmpty) {
      final override = decryptOverrides.removeAt(0);
      if (override != null) return override;
    }
    return utf8.decode(base64Decode(ciphertext.ciphertext));
  }

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
  }) async {
    if (throwOnVerify) throw StateError('crypto bridge unavailable');
    return signature ==
        base64Encode(utf8.encode('$senderSigningPublicKey:$canonicalData'));
  }
}

final class _RuntimeRoster implements CallTrustedRosterProvider {
  const _RuntimeRoster();

  @override
  Future<CallTrustedRosterSnapshot> loadForContact(String peerId) async =>
      throw UnimplementedError();

  @override
  Future<TrustedCallDeviceAuthority?> resolveAuthenticatedTransport(
    String transportPeerId,
  ) async => transportPeerId == 'sender-device'
      ? const TrustedCallDeviceAuthority(
          accountPeerId: 'sender-account',
          devicePeerId: 'sender-device',
          linked: true,
          deviceKeyEpoch: 1,
          signingPublicKey: 'sender-signing-key',
          mlKemPublicKey: 'sender-mlkem-key',
        )
      : null;
}

final class _RuntimePresenter implements IncomingCallPresenter {
  int presentations = 0;
  int dismissals = 0;

  @override
  Future<bool> present(IncomingCallPresentation presentation) async {
    presentations++;
    return true;
  }

  @override
  Future<void> dismiss(IncomingCallPresentation presentation) async {
    dismissals++;
  }
}

CallSignal _runtimeSignal({
  required String messageId,
  required CallSignalType event,
  required int sequence,
  int? expiresAtMs,
  Map<String, Object?> payload = const <String, Object?>{},
}) => CallSignal.create(
  callId: CallId.parse('22222222-2222-4222-8222-222222222222'),
  messageId: messageId,
  event: event,
  senderAccountPeerId: 'sender-account',
  senderDevicePeerId: 'sender-device',
  recipientAccountPeerId: 'recipient-account',
  recipientDevicePeerId: 'recipient-device',
  senderSequence: sequence,
  iceGeneration: 0,
  createdAtMs: _runtimeNowMs,
  expiresAtMs: expiresAtMs ?? _runtimeNowMs + 45_000,
  payload: payload,
);

Future<String> _runtimeEncodeUnchecked(
  _RuntimeCrypto crypto,
  CallSignal signal,
) async {
  const callHandle = '33333333-3333-4333-8333-333333333333';
  final encrypted = await crypto.encrypt(
    recipientMlKemPublicKey: 'recipient-mlkem-public',
    plaintext: jsonEncode(signal.toMap()),
  );
  final unsigned = <String, Object?>{
    'type': 'call_signal',
    'version': '1',
    'message_id': signal.messageId,
    'call_handle': callHandle,
    'expires_at_ms': signal.expiresAtMs,
    'kem': encrypted.kem,
    'ciphertext': encrypted.ciphertext,
    'nonce': encrypted.nonce,
  };
  final sortedKeys = unsigned.keys.toList()..sort();
  final canonical = jsonEncode(<String, Object?>{
    for (final key in sortedKeys) key: unsigned[key],
  });
  final signature = await crypto.sign(
    senderSigningPrivateKey: 'sender-signing-key',
    canonicalData: canonical,
  );
  return jsonEncode(<String, Object?>{...unsigned, 'signature': signature});
}

Future<
  ({
    CallSignalingRuntime runtime,
    CallCoordinator coordinator,
    _RuntimePresenter presenter,
    SecureCallEnvelopeCodec codec,
    CallSignalingContextStore signalingContexts,
    List<IncomingCallSignalOutcome> outcomes,
  })
>
_runtimeWithRealHandler({
  required Stream<ChatMessage> directStream,
  required _Mailbox mailbox,
  required _RuntimeCrypto crypto,
  CallEffectExecutor effects = const NoopCallEffectExecutor(),
  PrepareCallMailboxSettlement? prepareMailboxSettlement,
}) async {
  final coordinator = _coordinator(effects: effects);
  final presenter = _RuntimePresenter();
  final signalingContexts = CallSignalingContextStore();
  final outcomes = <IncomingCallSignalOutcome>[];
  final codec = SecureCallEnvelopeCodec(
    crypto: crypto,
    nowMs: () => _runtimeNowMs,
  );
  final handler = HandleIncomingCallSignal(
    codec: codec,
    coordinator: coordinator,
    trustedRosterProvider: const _RuntimeRoster(),
    localAuthorityProvider: () async => const CallLocalDeviceAuthority(
      accountPeerId: 'recipient-account',
      devicePeerId: 'recipient-device',
      mlKemSecretKey: 'recipient-mlkem-secret',
    ),
    incomingCallPresenter: presenter,
    networkEffectsAllowed: () => true,
    signalingContextObserver: signalingContexts,
  );
  return (
    runtime: CallSignalingRuntime(
      directCallSignalStream: directStream,
      mailboxClient: mailbox,
      handleIncoming: (frame) async {
        final outcome = await handler.handle(frame);
        outcomes.add(outcome);
        return outcome;
      },
      handleMailboxIncoming: (frame) async {
        final result = await handler.handleMailbox(frame);
        outcomes.add(result.outcome);
        return result;
      },
      prepareMailboxSettlement: prepareMailboxSettlement,
      coordinator: coordinator,
      networkEffectsAllowed: () => true,
    ),
    coordinator: coordinator,
    presenter: presenter,
    codec: codec,
    signalingContexts: signalingContexts,
    outcomes: outcomes,
  );
}

final class _AdmissionPort implements AndroidCallAdmissionSettlementPort {
  bool available = true;
  bool foreground = true;
  int captures = 0;
  int commits = 0;
  String owner = '77777777-7777-4777-8777-777777777777';
  String handle = '33333333-3333-4333-8333-333333333333';
  String wake = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  Future<void>? captureBarrier;
  final captureEntered = Completer<void>();
  @override
  bool get admissionSettlementAvailable => available;
  @override
  Future<AndroidCallAdmissionToken?> captureAdmissionSettlement(
    String nativeCallId,
  ) async {
    captures++;
    final token = AndroidCallAdmissionToken.fromWire(<String, Object?>{
      'nativeCallId': handle,
      'ownerId': owner,
      'expiresAtMs': _runtimeNowMs + 600000,
      'wakeHandle': wake,
    });
    if (!captureEntered.isCompleted) captureEntered.complete();
    await captureBarrier;
    return token;
  }

  @override
  Future<bool> settleAuthenticatedAdmission(
    AndroidCallAdmissionToken token,
  ) async {
    commits++;
    if (!available ||
        token.ownerId != owner ||
        token.nativeCallId != handle ||
        token.wakeHandle != wake) {
      return false;
    }
    foreground = false;
    return true;
  }
}

final class _IssuedWakeStore implements IssuedCallWakeHandleStore {
  CallIssuedWakeHandleRecord? record = CallIssuedWakeHandleRecord(
    contactAccountPeerId: 'sender-account',
    grant: CallWakeHandleGrant(
      handle: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      recipientDevicePeerId: 'recipient-device',
      deviceKeyEpoch: 1,
      generation: 1,
      issuedAtMs: _runtimeNowMs - 1,
      expiresAtMs: _runtimeNowMs + 3600000,
    ),
    authorizedSenderDevicePeerIds: const <String>['sender-device'],
    distributionPending: false,
    distributionReceiptVersion: 1,
  );
  Future<void>? barrier;
  final readEntered = Completer<void>();
  int reads = 0;
  Future<void>? finalReadBarrier;
  final finalReadEntered = Completer<void>();
  @override
  Future<CallIssuedWakeHandleRecord?> readForContact(
    String contactAccountPeerId,
  ) async {
    reads++;
    if (!readEntered.isCompleted) readEntered.complete();
    await barrier;
    if (reads == 2) {
      if (!finalReadEntered.isCompleted) finalReadEntered.complete();
      await finalReadBarrier;
    }
    return record?.contactAccountPeerId == contactAccountPeerId ? record : null;
  }

  @override
  Future<List<CallIssuedWakeHandleRecord>> readAll() async => [?record];
  @override
  Future<void> write(CallIssuedWakeHandleRecord value) async => record = value;
  @override
  Future<void> removeForContact(String contactAccountPeerId) async =>
      record = null;
  @override
  Future<void> clear() async => record = null;
}

Future<CallMailboxEvent> _terminalMailboxEvent(
  SecureCallEnvelopeCodec codec, {
  CallSignalType type = CallSignalType.terminate,
  String frameHandle = '33333333-3333-4333-8333-333333333333',
  String frameSender = 'sender-device',
  String frameRecipient = 'recipient-device',
  String? frameMessageId,
  int? frameExpiry,
  bool invalidSignature = false,
}) async {
  final signal = _runtimeSignal(
    messageId: '55555555-5555-4555-8555-555555555555',
    event: type,
    sequence: 2,
    payload: <String, Object?>{
      'reason': type == CallSignalType.reject ? 'declined' : 'remote_hangup',
    },
  );
  var envelope = await codec.encode(
    signal: signal,
    callHandle: '33333333-3333-4333-8333-333333333333',
    recipientMlKemPublicKey: 'recipient-mlkem-public',
    senderSigningPrivateKey: 'sender-signing-key',
  );
  if (invalidSignature) {
    final object = jsonDecode(envelope) as Map<String, dynamic>;
    object['signature'] = base64Encode(utf8.encode('untrusted'));
    envelope = jsonEncode(object);
  }
  return CallMailboxEvent(
    callHandle: frameHandle,
    messageId: frameMessageId ?? signal.messageId,
    authenticatedSenderDevicePeerId: frameSender,
    recipientDevicePeerId: frameRecipient,
    envelopeJson: envelope,
    receiptAtMs: _runtimeNowMs,
    expiresAtMs: frameExpiry ?? signal.expiresAtMs,
  );
}

void _queueEvent(_Mailbox mailbox, CallMailboxEvent event) => mailbox.pages.add(
  CallMailboxRetrieveResult(
    events: [event],
    receiptAtMs: _runtimeNowMs,
    expiresAtMs: event.expiresAtMs,
    hasMore: false,
  ),
);

void main() {
  for (final variant in <String>[
    'terminate',
    'reject',
    'signature',
    'sender',
    'recipient',
    'message',
    'expiry',
    'old_handle',
    'native_successor',
    'wake_mismatch',
    'unauthorized_device',
    'revoked',
    'account_changed',
    'already_active',
    'crypto_unavailable',
    'empty',
    'zero_ack',
    'grant_rotates',
  ]) {
    test('native terminal settlement preserves $variant authority', () async {
      final stream = StreamController<ChatMessage>.broadcast();
      addTearDown(stream.close);
      final mailbox = _Mailbox();
      final native = _AdmissionPort();
      final grants = _IssuedWakeStore();
      if (variant == 'native_successor') {
        native.handle = '66666666-6666-4666-8666-666666666666';
      }
      if (variant == 'wake_mismatch') {
        native.wake = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      }
      if (variant == 'unauthorized_device') {
        grants.record = grants.record!.copyWith(
          authorizedSenderDevicePeerIds: ['other-device'],
        );
      }
      if (variant == 'revoked') {
        grants.record = grants.record!.copyWith(revokePending: true);
      }
      if (variant == 'already_active') native.available = false;
      if (variant == 'zero_ack') mailbox.ackResult = 0;
      var accountReads = 0;
      final built = await _runtimeWithRealHandler(
        directStream: stream.stream,
        mailbox: mailbox,
        crypto: _RuntimeCrypto()
          ..throwOnVerify = variant == 'crypto_unavailable',
        prepareMailboxSettlement: (frame) =>
            prepareAndroidCallAdmissionSettlement(
              frame: frame,
              native: native,
              issuedWakeHandles: grants,
              localAccountPeerId: 'recipient-account',
              localDevicePeerId: 'recipient-device',
              localDeviceKeyEpoch: 1,
              isCurrentLocalAuthority: () async {
                accountReads++;
                if (variant == 'grant_rotates' && accountReads == 2) {
                  grants.record = grants.record!.copyWith(revokePending: true);
                }
                return variant != 'account_changed';
              },
              nowMs: () => _runtimeNowMs,
            ),
      );
      addTearDown(built.runtime.shutdown);
      final event = await _terminalMailboxEvent(
        built.codec,
        type: variant == 'reject'
            ? CallSignalType.reject
            : CallSignalType.terminate,
        invalidSignature: variant == 'signature',
        frameHandle: variant == 'old_handle'
            ? '66666666-6666-4666-8666-666666666666'
            : '33333333-3333-4333-8333-333333333333',
        frameSender: variant == 'sender' ? 'other-device' : 'sender-device',
        frameRecipient: variant == 'recipient'
            ? 'other-recipient'
            : 'recipient-device',
        frameMessageId: variant == 'message'
            ? '66666666-6666-4666-8666-666666666666'
            : null,
        frameExpiry: variant == 'expiry' ? _runtimeNowMs + 45001 : null,
      );
      if (variant != 'empty') _queueEvent(mailbox, event);
      await built.runtime.start();
      final succeeds = variant == 'terminate' || variant == 'reject';
      expect(native.foreground, !succeeds);
      expect(native.commits, succeeds ? 1 : 0);
      expect(
        mailbox.acks,
        const ['empty', 'crypto_unavailable', 'zero_ack'].contains(variant)
            ? 0
            : 1,
      );
      expect(built.presenter.presentations, 0);
      expect(built.coordinator.activeSession, isNull);
    });
  }

  test(
    'account cutover during final grant read prevents native settlement',
    () async {
      final stream = StreamController<ChatMessage>.broadcast();
      addTearDown(stream.close);
      final mailbox = _Mailbox();
      final native = _AdmissionPort();
      final gate = Completer<void>();
      final grants = _IssuedWakeStore()..finalReadBarrier = gate.future;
      var authorityCurrent = true;
      final built = await _runtimeWithRealHandler(
        directStream: stream.stream,
        mailbox: mailbox,
        crypto: _RuntimeCrypto(),
        prepareMailboxSettlement: (frame) =>
            prepareAndroidCallAdmissionSettlement(
              frame: frame,
              native: native,
              issuedWakeHandles: grants,
              localAccountPeerId: 'recipient-account',
              localDevicePeerId: 'recipient-device',
              localDeviceKeyEpoch: 1,
              isCurrentLocalAuthority: () async => authorityCurrent,
              nowMs: () => _runtimeNowMs,
            ),
      );
      addTearDown(built.runtime.shutdown);
      _queueEvent(mailbox, await _terminalMailboxEvent(built.codec));
      final starting = built.runtime.start();
      await grants.finalReadEntered.future;
      authorityCurrent = false;
      gate.complete();
      await starting;
      expect(mailbox.acks, 1);
      expect(native.commits, 0);
      expect(native.foreground, isTrue);
    },
  );

  for (final replacement in <bool>[false, true]) {
    test(
      'failed ACK retains original settlement token across replay replacement=$replacement',
      () async {
        final stream = StreamController<ChatMessage>.broadcast();
        addTearDown(stream.close);
        final mailbox = _Mailbox()..failAcks = true;
        final native = _AdmissionPort();
        final grants = _IssuedWakeStore();
        final built = await _runtimeWithRealHandler(
          directStream: stream.stream,
          mailbox: mailbox,
          crypto: _RuntimeCrypto(),
          prepareMailboxSettlement: (frame) =>
              prepareAndroidCallAdmissionSettlement(
                frame: frame,
                native: native,
                issuedWakeHandles: grants,
                localAccountPeerId: 'recipient-account',
                localDevicePeerId: 'recipient-device',
                localDeviceKeyEpoch: 1,
                isCurrentLocalAuthority: () async => true,
                nowMs: () => _runtimeNowMs,
              ),
        );
        addTearDown(built.runtime.shutdown);
        final event = await _terminalMailboxEvent(built.codec);
        _queueEvent(mailbox, event);
        await built.runtime.start();
        expect(native.foreground, isTrue);
        expect(native.commits, 0);
        if (replacement) native.owner = '88888888-8888-4888-8888-888888888888';
        mailbox.failAcks = false;
        _queueEvent(mailbox, event);
        await built.runtime.onResume();
        expect(
          native.captures,
          1,
          reason: 'Replay must never capture a replacement WorkRequest',
        );
        expect(native.commits, 1);
        expect(native.foreground, replacement);
        expect(mailbox.acks, 1);
      },
    );
  }

  for (final phase in <String>['capture', 'ack', 'grant']) {
    test(
      'shutdown during $phase prevents late native admission settlement',
      () async {
        final stream = StreamController<ChatMessage>.broadcast();
        addTearDown(stream.close);
        final gate = Completer<void>();
        final mailbox = _Mailbox();
        final native = _AdmissionPort();
        final grants = _IssuedWakeStore();
        if (phase == 'capture') native.captureBarrier = gate.future;
        if (phase == 'ack') mailbox.ackBarrier = gate.future;
        if (phase == 'grant') grants.barrier = gate.future;
        final built = await _runtimeWithRealHandler(
          directStream: stream.stream,
          mailbox: mailbox,
          crypto: _RuntimeCrypto(),
          prepareMailboxSettlement: (frame) =>
              prepareAndroidCallAdmissionSettlement(
                frame: frame,
                native: native,
                issuedWakeHandles: grants,
                localAccountPeerId: 'recipient-account',
                localDevicePeerId: 'recipient-device',
                localDeviceKeyEpoch: 1,
                isCurrentLocalAuthority: () async => true,
                nowMs: () => _runtimeNowMs,
              ),
        );
        addTearDown(built.runtime.shutdown);
        _queueEvent(mailbox, await _terminalMailboxEvent(built.codec));
        final starting = built.runtime.start();
        await switch (phase) {
          'capture' => native.captureEntered.future,
          'ack' => mailbox.ackEntered.future,
          _ => grants.readEntered.future,
        };
        final closing = built.runtime.shutdown();
        gate.complete();
        await starting;
        await closing;
        expect(native.commits, 0);
        expect(native.foreground, isTrue);
      },
    );
  }
  test(
    'foreground terminal ACK retires deferred native admission without a canonical session',
    () async {
      final stream = StreamController<ChatMessage>.broadcast();
      addTearDown(stream.close);
      final mailbox = _Mailbox();
      var admissionForeground = true;
      var captures = 0;
      var settlements = 0;
      final built = await _runtimeWithRealHandler(
        directStream: stream.stream,
        mailbox: mailbox,
        crypto: _RuntimeCrypto(),
        prepareMailboxSettlement: (frame) async {
          captures++;
          expect(mailbox.acks, 0);
          return (terminal, {required canApply}) async {
            expect(
              mailbox.acks,
              1,
              reason: 'Durable mailbox ACK precedes native release',
            );
            expect(terminal.callHandle, frame.expectedCallHandle);
            expect(terminal.signal.messageId, frame.expectedMessageId);
            expect(terminal.signal.event, CallSignalType.terminate);
            settlements++;
            admissionForeground = false;
          };
        },
      );
      addTearDown(built.runtime.shutdown);
      final terminal = _runtimeSignal(
        messageId: '55555555-5555-4555-8555-555555555555',
        event: CallSignalType.terminate,
        sequence: 2,
        payload: const <String, Object?>{'reason': 'remote_hangup'},
      );
      final envelope = await built.codec.encode(
        signal: terminal,
        callHandle: '33333333-3333-4333-8333-333333333333',
        recipientMlKemPublicKey: 'recipient-mlkem-public',
        senderSigningPrivateKey: 'sender-signing-key',
      );
      mailbox.pages.add(
        CallMailboxRetrieveResult(
          events: <CallMailboxEvent>[
            CallMailboxEvent(
              callHandle: '33333333-3333-4333-8333-333333333333',
              messageId: terminal.messageId,
              authenticatedSenderDevicePeerId: 'sender-device',
              recipientDevicePeerId: 'recipient-device',
              envelopeJson: envelope,
              receiptAtMs: _runtimeNowMs,
              expiresAtMs: terminal.expiresAtMs,
            ),
          ],
          receiptAtMs: _runtimeNowMs,
          expiresAtMs: terminal.expiresAtMs,
          hasMore: false,
        ),
      );
      expect(built.coordinator.activeSession, isNull);
      await built.runtime.start();
      expect(mailbox.acks, 1);
      expect(built.presenter.presentations, 0);
      expect(built.coordinator.activeSession, isNull);
      expect(
        admissionForeground,
        isFalse,
        reason:
            'graph_not_owner custody is completed by the authenticated foreground terminal',
      );
      expect(captures, 1);
      expect(settlements, 1);
    },
  );
  for (final useMailbox in <bool>[false, true]) {
    test(
      '${useMailbox ? 'mailbox' : 'direct'} hang-up interrupts admitted accept preparation',
      () async {
        final stream = StreamController<ChatMessage>.broadcast();
        addTearDown(stream.close);
        final mailbox = _Mailbox();
        final effects = _PendingMediaEffects();
        final built = await _runtimeWithRealHandler(
          directStream: stream.stream,
          mailbox: mailbox,
          crypto: _RuntimeCrypto(),
          effects: effects,
        );
        addTearDown(() {
          if (!effects.release.isCompleted) effects.release.complete();
          return built.runtime.shutdown();
        });
        await built.runtime.start();
        final accept = _runtimeSignal(
          messageId: '44444444-4444-4444-8444-444444444444',
          event: CallSignalType.accept,
          sequence: 1,
        );
        await built.coordinator.dispatch(
          CallEvent(
            type: CallEventType.place,
            eventId: 'outgoing',
            occurredAt: _runtimeNow,
            callId: accept.callId,
            contactPeerId: 'sender-account',
            localAccountPeerId: 'recipient-account',
            localDeviceId: 'recipient-device',
            remoteAccountPeerId: 'sender-account',
          ),
        );
        await built.coordinator.dispatch(
          CallEvent(
            type: CallEventType.outgoingInviteReady,
            eventId: 'outgoing-ready',
            occurredAt: _runtimeNow,
            callId: accept.callId,
            contactPeerId: 'sender-account',
          ),
        );
        final terminate = _runtimeSignal(
          messageId: '55555555-5555-4555-8555-555555555555',
          event: CallSignalType.terminate,
          sequence: 2,
          payload: const <String, Object?>{'reason': 'remote_hangup'},
        );
        Future<void> deliver(CallSignal signal) async {
          final envelope = await built.codec.encode(
            signal: signal,
            callHandle: '33333333-3333-4333-8333-333333333333',
            recipientMlKemPublicKey: 'recipient-mlkem-public',
            senderSigningPrivateKey: 'sender-signing-key',
          );
          if (useMailbox) {
            mailbox.pages.add(
              CallMailboxRetrieveResult(
                events: <CallMailboxEvent>[
                  CallMailboxEvent(
                    callHandle: '33333333-3333-4333-8333-333333333333',
                    messageId: signal.messageId,
                    envelopeJson: envelope,
                    authenticatedSenderDevicePeerId: 'sender-device',
                    recipientDevicePeerId: 'recipient-device',
                    receiptAtMs: _runtimeNowMs,
                    expiresAtMs: signal.expiresAtMs,
                  ),
                ],
                receiptAtMs: _runtimeNowMs,
                expiresAtMs: signal.expiresAtMs,
                hasMore: false,
              ),
            );
            await built.runtime.onResume();
          } else {
            stream.add(
              ChatMessage(
                from: 'sender-device',
                to: 'recipient-device',
                content: envelope,
                timestamp: '2026-08-30T00:00:00.000Z',
                isIncoming: true,
                transport: 'direct',
              ),
            );
            await Future<void>.delayed(Duration.zero);
            await built.runtime.settle();
          }
        }

        await deliver(accept).timeout(const Duration(seconds: 1));
        await effects.preparing.future;
        expect(effects.release.isCompleted, isFalse);
        await deliver(terminate).timeout(const Duration(seconds: 1));
        expect(built.coordinator.activeSession, isNull);
        expect(built.coordinator.lastSnapshot?.isTerminal, isTrue);
        expect(built.outcomes, <IncomingCallSignalOutcome>[
          IncomingCallSignalOutcome.accepted,
          IncomingCallSignalOutcome.accepted,
        ]);
        if (useMailbox) expect(mailbox.acks, 2);
        effects.release.complete();
        await Future<void>.delayed(Duration.zero);
        expect(built.coordinator.activeSession, isNull);
        expect(
          built.coordinator.lastSnapshot?.recentEventIds,
          isNot(contains('late-negotiation')),
        );
      },
    );
  }

  test(
    'migration readiness precedes listener and cold-start mailbox drain',
    () async {
      final stream = StreamController<ChatMessage>.broadcast();
      addTearDown(stream.close);
      final mailbox = _Mailbox()
        ..pages.add(
          CallMailboxRetrieveResult(
            events: <CallMailboxEvent>[],
            receiptAtMs: 0,
            expiresAtMs: 0,
            hasMore: false,
          ),
        );
      var allowed = false;
      final coordinator = _coordinator();
      final runtime = CallSignalingRuntime(
        directCallSignalStream: stream.stream,
        mailboxClient: mailbox,
        handleIncoming: (_) async => IncomingCallSignalOutcome.accepted,
        coordinator: coordinator,
        networkEffectsAllowed: () async => allowed,
      );

      expect(await runtime.start(), isFalse);
      expect(runtime.isStarted, isFalse);
      expect(stream.hasListener, isFalse);
      expect(mailbox.retrieves, 0);

      allowed = true;
      expect(await runtime.start(), isTrue);
      expect(runtime.isStarted, isTrue);
      expect(stream.hasListener, isTrue);
      expect(mailbox.retrieves, 1);

      expect(await runtime.start(), isTrue);
      expect(stream.hasListener, isTrue);
      expect(mailbox.retrieves, 1);

      await runtime.onResume();
      expect(mailbox.retrieves, 2);
      await runtime.shutdown();
    },
  );

  test(
    'throwing start gate fails closed and a later retry can subscribe',
    () async {
      final stream = StreamController<ChatMessage>.broadcast();
      addTearDown(stream.close);
      var gateCalls = 0;
      final runtime = CallSignalingRuntime(
        directCallSignalStream: stream.stream,
        mailboxClient: _Mailbox(),
        handleIncoming: (_) async => IncomingCallSignalOutcome.rejected,
        coordinator: _coordinator(),
        networkEffectsAllowed: () {
          gateCalls++;
          if (gateCalls == 1) throw StateError('migration gate unavailable');
          return true;
        },
      );

      expect(await runtime.start(), isFalse);
      expect(runtime.isStarted, isFalse);
      expect(stream.hasListener, isFalse);

      expect(await runtime.start(), isTrue);
      expect(await runtime.start(), isTrue);
      expect(runtime.isStarted, isTrue);
      expect(stream.hasListener, isTrue);
      expect(
        gateCalls,
        2,
        reason: 'already-started calls do not re-run the gate',
      );
      await runtime.shutdown();
    },
  );

  test(
    'concurrent starts share one gate attempt and one subscription',
    () async {
      var listenerCount = 0;
      final stream = StreamController<ChatMessage>.broadcast(
        onListen: () => listenerCount++,
      );
      addTearDown(stream.close);
      final gate = Completer<bool>();
      var gateCalls = 0;
      final runtime = CallSignalingRuntime(
        directCallSignalStream: stream.stream,
        mailboxClient: _Mailbox(),
        handleIncoming: (_) async => IncomingCallSignalOutcome.rejected,
        coordinator: _coordinator(),
        networkEffectsAllowed: () {
          gateCalls++;
          return gate.future;
        },
      );

      final first = runtime.start();
      final second = runtime.start();
      await Future<void>.delayed(Duration.zero);
      expect(gateCalls, 1);
      gate.complete(true);

      expect(await Future.wait(<Future<bool>>[first, second]), <bool>[
        true,
        true,
      ]);
      expect(listenerCount, 1);
      expect(runtime.isStarted, isTrue);
      await runtime.shutdown();
      expect(await runtime.start(), isFalse);
    },
  );

  test(
    'direct and duplicate mailbox wake serialize into one call-only lane',
    () async {
      final stream = StreamController<ChatMessage>.broadcast();
      addTearDown(stream.close);
      const handle = '33333333-3333-4333-8333-333333333333';
      const message = '11111111-1111-4111-8111-111111111111';
      final mailbox = _Mailbox();
      final frames = <IncomingCallSignalFrame>[];
      final coordinator = _coordinator();
      final runtime = CallSignalingRuntime(
        directCallSignalStream: stream.stream,
        mailboxClient: mailbox,
        handleIncoming: (frame) async {
          frames.add(frame);
          return frames.length == 1
              ? IncomingCallSignalOutcome.accepted
              : IncomingCallSignalOutcome.duplicate;
        },
        coordinator: coordinator,
        networkEffectsAllowed: () => true,
      );
      await runtime.start();
      await runtime.start();

      mailbox.pages.add(
        CallMailboxRetrieveResult(
          events: <CallMailboxEvent>[
            CallMailboxEvent(
              callHandle: handle,
              messageId: message,
              authenticatedSenderDevicePeerId: 'sender-device',
              recipientDevicePeerId: 'recipient-device',
              envelopeJson: '{"type":"call_signal"}',
              receiptAtMs: 1,
              expiresAtMs: 2,
            ),
          ],
          receiptAtMs: 1,
          expiresAtMs: 2,
          hasMore: false,
        ),
      );

      stream.add(
        const ChatMessage(
          from: 'sender-device',
          to: 'recipient-device',
          content: '{"type":"call_signal"}',
          timestamp: '2026-08-30T00:00:00.000Z',
          isIncoming: true,
          transport: 'direct',
        ),
      );
      await runtime.settle();
      await runtime.onResume();

      expect(frames, hasLength(2));
      expect(frames.first.route.name, 'direct');
      expect(frames.last.expectedCallHandle, handle);
      expect(frames.last.expectedMessageId, message);
      expect(mailbox.acks, 1);
      await runtime.shutdown();
    },
  );

  test(
    'shutdown is idempotent and disposes only its own subscription',
    () async {
      final stream = StreamController<ChatMessage>.broadcast();
      addTearDown(stream.close);
      final coordinator = _coordinator();
      final runtime = CallSignalingRuntime(
        directCallSignalStream: stream.stream,
        mailboxClient: _Mailbox(),
        handleIncoming: (_) async => IncomingCallSignalOutcome.rejected,
        coordinator: coordinator,
        networkEffectsAllowed: () => true,
      );
      await runtime.start();
      expect(stream.hasListener, isTrue);

      await runtime.shutdown();
      await runtime.shutdown();

      expect(runtime.isDisposed, isTrue);
      expect(stream.hasListener, isFalse);
      expect(stream.isClosed, isFalse);
    },
  );

  test('deferred and throwing handlers retain mailbox custody', () async {
    for (final throwFromHandler in <bool>[false, true]) {
      final stream = StreamController<ChatMessage>.broadcast();
      const handle = '33333333-3333-4333-8333-333333333333';
      const message = '11111111-1111-4111-8111-111111111111';
      final mailbox = _Mailbox()
        ..pages.add(
          CallMailboxRetrieveResult(
            events: <CallMailboxEvent>[
              const CallMailboxEvent(
                callHandle: handle,
                messageId: message,
                authenticatedSenderDevicePeerId: 'sender-device',
                recipientDevicePeerId: 'recipient-device',
                envelopeJson: '{"type":"call_signal"}',
                receiptAtMs: 1,
                expiresAtMs: 2,
              ),
            ],
            receiptAtMs: 1,
            expiresAtMs: 2,
            hasMore: false,
          ),
        );
      final coordinator = _coordinator();
      final runtime = CallSignalingRuntime(
        directCallSignalStream: stream.stream,
        mailboxClient: mailbox,
        handleIncoming: (_) async {
          if (throwFromHandler) {
            throw StateError('temporary authority failure');
          }
          return IncomingCallSignalOutcome.deferred;
        },
        coordinator: coordinator,
        networkEffectsAllowed: () => true,
      );

      await runtime.start();
      await runtime.onResume();

      expect(mailbox.ackAttempts, 0, reason: 'case=$throwFromHandler');
      await runtime.shutdown();
      await stream.close();
    }
  });

  test('ACK failure stops the drain before later mailbox events', () async {
    final stream = StreamController<ChatMessage>.broadcast();
    addTearDown(stream.close);
    const handle = '33333333-3333-4333-8333-333333333333';
    final mailbox = _Mailbox()
      ..failAcks = true
      ..pages.add(
        CallMailboxRetrieveResult(
          events: <CallMailboxEvent>[
            for (var index = 0; index < 2; index++)
              CallMailboxEvent(
                callHandle: handle,
                messageId: index == 0
                    ? '11111111-1111-4111-8111-111111111111'
                    : '22222222-2222-4222-8222-222222222222',
                authenticatedSenderDevicePeerId: 'sender-device',
                recipientDevicePeerId: 'recipient-device',
                envelopeJson: '{"type":"call_signal"}',
                receiptAtMs: 1,
                expiresAtMs: 2,
              ),
          ],
          receiptAtMs: 1,
          expiresAtMs: 2,
          hasMore: false,
        ),
      );
    var handled = 0;
    final runtime = CallSignalingRuntime(
      directCallSignalStream: stream.stream,
      mailboxClient: mailbox,
      handleIncoming: (_) async {
        handled++;
        return IncomingCallSignalOutcome.accepted;
      },
      coordinator: _coordinator(),
      networkEffectsAllowed: () => true,
    );

    await runtime.start();
    await runtime.onResume();

    expect(handled, 1);
    expect(mailbox.ackAttempts, 1);
    expect(mailbox.acks, 0);
    await runtime.shutdown();
  });

  test('direct flood is fail-closed at the pending operation bound', () async {
    final stream = StreamController<ChatMessage>.broadcast();
    addTearDown(stream.close);
    final release = Completer<void>();
    var handled = 0;
    final runtime = CallSignalingRuntime(
      directCallSignalStream: stream.stream,
      mailboxClient: _Mailbox(),
      handleIncoming: (_) async {
        handled++;
        await release.future;
        return IncomingCallSignalOutcome.rejected;
      },
      coordinator: _coordinator(),
      networkEffectsAllowed: () => true,
      maxPendingOperations: 2,
    );
    await runtime.start();

    for (var index = 0; index < 10; index++) {
      stream.add(
        const ChatMessage(
          from: 'sender-device',
          to: 'recipient-device',
          content: '{"type":"call_signal"}',
          timestamp: '2026-08-30T00:00:00.000Z',
          isIncoming: true,
          transport: 'direct',
        ),
      );
    }
    await Future<void>.delayed(Duration.zero);
    release.complete();
    await runtime.settle();

    expect(handled, 2);
    await runtime.shutdown();
  });

  test('resume flood is fail-closed at the same pending bound', () async {
    final stream = StreamController<ChatMessage>.broadcast();
    addTearDown(stream.close);
    final release = Completer<void>();
    final mailbox = _Mailbox();
    final runtime = CallSignalingRuntime(
      directCallSignalStream: stream.stream,
      mailboxClient: mailbox,
      handleIncoming: (_) async => IncomingCallSignalOutcome.rejected,
      coordinator: _coordinator(),
      networkEffectsAllowed: () => true,
      maxPendingOperations: 2,
    );
    await runtime.start();
    mailbox.retrieves = 0;
    mailbox.retrieveBarrier = release.future;

    final resumes = <Future<void>>[
      for (var index = 0; index < 10; index++) runtime.onResume(),
    ];
    await Future<void>.delayed(Duration.zero);
    release.complete();
    await Future.wait(resumes);

    expect(mailbox.retrieves, 2);
    await runtime.shutdown();
  });

  test(
    'transient crypto exception retains mailbox custody until retry succeeds',
    () async {
      for (final phase in <String>['verify', 'decrypt']) {
        final stream = StreamController<ChatMessage>.broadcast();
        final mailbox = _Mailbox();
        final crypto = _RuntimeCrypto();
        final built = await _runtimeWithRealHandler(
          directStream: stream.stream,
          mailbox: mailbox,
          crypto: crypto,
        );
        final signal = _runtimeSignal(
          messageId: '11111111-1111-4111-8111-111111111111',
          event: CallSignalType.invite,
          sequence: 1,
        );
        final envelope = await built.codec.encode(
          signal: signal,
          callHandle: '33333333-3333-4333-8333-333333333333',
          recipientMlKemPublicKey: 'recipient-mlkem-public',
          senderSigningPrivateKey: 'sender-signing-key',
        );
        CallMailboxRetrieveResult page() => CallMailboxRetrieveResult(
          events: <CallMailboxEvent>[
            CallMailboxEvent(
              callHandle: '33333333-3333-4333-8333-333333333333',
              messageId: signal.messageId,
              authenticatedSenderDevicePeerId: 'sender-device',
              recipientDevicePeerId: 'recipient-device',
              envelopeJson: envelope,
              receiptAtMs: _runtimeNowMs,
              expiresAtMs: signal.expiresAtMs,
            ),
          ],
          receiptAtMs: _runtimeNowMs,
          expiresAtMs: signal.expiresAtMs,
          hasMore: false,
        );
        mailbox.pages.add(page());
        crypto.throwOnVerify = phase == 'verify';
        crypto.throwOnDecrypt = phase == 'decrypt';

        await built.runtime.start();
        await built.runtime.onResume();
        expect(mailbox.ackAttempts, 0, reason: phase);
        expect(built.coordinator.activeSession, isNull, reason: phase);

        crypto.throwOnVerify = false;
        crypto.throwOnDecrypt = false;
        mailbox.pages.add(page());
        await built.runtime.onResume();

        expect(mailbox.acks, 1, reason: phase);
        expect(built.coordinator.activeSession?.state, CallState.ringing);
        expect(built.presenter.presentations, 1, reason: phase);
        await built.runtime.shutdown();
        await stream.close();
      }
    },
  );

  test(
    'ICE sequence 3 before offer sequence 2 still processes the unseen offer',
    () async {
      final stream = StreamController<ChatMessage>.broadcast();
      addTearDown(stream.close);
      final mailbox = _Mailbox();
      final crypto = _RuntimeCrypto();
      final built = await _runtimeWithRealHandler(
        directStream: stream.stream,
        mailbox: mailbox,
        crypto: crypto,
      );
      addTearDown(built.runtime.shutdown);

      final invite = _runtimeSignal(
        messageId: '11111111-1111-4111-8111-111111111111',
        event: CallSignalType.invite,
        sequence: 1,
      );
      final ice = _runtimeSignal(
        messageId: '55555555-5555-4555-8555-555555555555',
        event: CallSignalType.ice,
        sequence: 3,
        payload: const <String, Object?>{
          'candidate': 'candidate:fixture',
          'media_id': 'audio',
          'media_line_index': 0,
        },
      );
      final offer = _runtimeSignal(
        messageId: '44444444-4444-4444-8444-444444444444',
        event: CallSignalType.offer,
        sequence: 2,
        payload: const <String, Object?>{
          'description': 'opaque-offer',
          'fingerprint': 'sha-256 fixture',
        },
      );
      final reusedSequence = _runtimeSignal(
        messageId: '66666666-6666-4666-8666-666666666666',
        event: CallSignalType.offer,
        sequence: 2,
        payload: const <String, Object?>{
          'description': 'different-opaque-offer',
          'fingerprint': 'sha-256 fixture',
        },
      );

      Future<String> encode(CallSignal signal) => built.codec.encode(
        signal: signal,
        callHandle: '33333333-3333-4333-8333-333333333333',
        recipientMlKemPublicKey: 'recipient-mlkem-public',
        senderSigningPrivateKey: 'sender-signing-key',
      );

      Future<void> deliver(String envelope) async {
        stream.add(
          ChatMessage(
            from: 'sender-device',
            to: 'recipient-device',
            content: envelope,
            timestamp: '2026-08-30T00:00:00.000Z',
            isIncoming: true,
            transport: 'direct',
          ),
        );
        await Future<void>.delayed(Duration.zero);
        await built.runtime.settle();
      }

      await built.runtime.start();
      final inviteEnvelope = await encode(invite);
      final iceEnvelope = await encode(ice);
      final offerEnvelope = await encode(offer);
      final reusedSequenceEnvelope = await encode(reusedSequence);

      await deliver(inviteEnvelope);
      expect(built.coordinator.activeSession?.state, CallState.ringing);
      await built.coordinator.dispatch(
        CallEvent(
          type: CallEventType.answer,
          eventId: 'local-answer',
          occurredAt: _runtimeNow,
          callId: invite.callId,
          contactPeerId: invite.senderAccountPeerId,
          remoteAccountPeerId: invite.senderAccountPeerId,
          remoteDeviceId: invite.senderDevicePeerId,
        ),
      );
      expect(built.coordinator.activeSession?.state, CallState.accepted);

      await deliver(iceEnvelope);
      expect(
        built.signalingContexts.read(invite.callId)?.remoteSenderSequence,
        3,
      );
      expect(built.coordinator.activeSession?.state, CallState.accepted);

      await deliver(offerEnvelope);
      expect(built.coordinator.activeSession?.state, CallState.negotiating);
      expect(
        built.coordinator.activeSession?.recentEventIds,
        contains(offer.messageId),
      );
      expect(
        built.signalingContexts.read(invite.callId)?.remoteSenderSequence,
        3,
      );

      await deliver(offerEnvelope);
      await deliver(reusedSequenceEnvelope);

      expect(built.outcomes, <IncomingCallSignalOutcome>[
        IncomingCallSignalOutcome.accepted,
        IncomingCallSignalOutcome.accepted,
        IncomingCallSignalOutcome.accepted,
        IncomingCallSignalOutcome.duplicate,
        IncomingCallSignalOutcome.duplicate,
      ]);
      expect(
        built.coordinator.activeSession?.recentEventIds,
        isNot(contains(reusedSequence.messageId)),
      );
      expect(
        built.signalingContexts.read(invite.callId)?.remoteSenderSequence,
        3,
      );
    },
  );

  test(
    'far-future signed signal is permanently ACKed without blocking next event',
    () async {
      final stream = StreamController<ChatMessage>.broadcast();
      addTearDown(stream.close);
      final mailbox = _Mailbox();
      final crypto = _RuntimeCrypto();
      final built = await _runtimeWithRealHandler(
        directStream: stream.stream,
        mailbox: mailbox,
        crypto: crypto,
      );
      addTearDown(built.runtime.shutdown);
      final farFuture = _runtimeSignal(
        messageId: '11111111-1111-4111-8111-111111111111',
        event: CallSignalType.offer,
        sequence: 1,
        expiresAtMs: 9000000000000000,
        payload: const <String, Object?>{
          'description': 'opaque-offer',
          'fingerprint': 'sha-256 fixture',
        },
      );
      final invite = _runtimeSignal(
        messageId: '44444444-4444-4444-8444-444444444444',
        event: CallSignalType.invite,
        sequence: 2,
      );
      final farEnvelope = await _runtimeEncodeUnchecked(crypto, farFuture);
      final inviteEnvelope = await built.codec.encode(
        signal: invite,
        callHandle: '33333333-3333-4333-8333-333333333333',
        recipientMlKemPublicKey: 'recipient-mlkem-public',
        senderSigningPrivateKey: 'sender-signing-key',
      );
      mailbox.pages.add(
        CallMailboxRetrieveResult(
          events: <CallMailboxEvent>[
            CallMailboxEvent(
              callHandle: '33333333-3333-4333-8333-333333333333',
              messageId: farFuture.messageId,
              authenticatedSenderDevicePeerId: 'sender-device',
              recipientDevicePeerId: 'recipient-device',
              envelopeJson: farEnvelope,
              receiptAtMs: _runtimeNowMs,
              expiresAtMs: farFuture.expiresAtMs,
            ),
            CallMailboxEvent(
              callHandle: '33333333-3333-4333-8333-333333333333',
              messageId: invite.messageId,
              authenticatedSenderDevicePeerId: 'sender-device',
              recipientDevicePeerId: 'recipient-device',
              envelopeJson: inviteEnvelope,
              receiptAtMs: _runtimeNowMs,
              expiresAtMs: invite.expiresAtMs,
            ),
          ],
          receiptAtMs: _runtimeNowMs,
          expiresAtMs: invite.expiresAtMs,
          hasMore: false,
        ),
      );

      await built.runtime.start();
      await built.runtime.onResume();

      expect(mailbox.acks, 2);
      expect(built.coordinator.activeSession?.state, CallState.ringing);
      expect(built.presenter.presentations, 1);
    },
  );

  test(
    'runtime still finalizes when coordinator shutdown reports failure',
    () async {
      final stream = StreamController<ChatMessage>.broadcast();
      addTearDown(stream.close);
      final coordinator = CallCoordinator(
        reducer: const CallReducer(),
        cleanupCoordinator: CallCleanupCoordinator(const <CallCleanupStep>[]),
        historyProjector: CallHistoryProjector(_ThrowingRuntimeHistory()),
        clock: () => _runtimeNow,
        idSource: () => CallId.parse('22222222-2222-4222-8222-222222222222'),
      );
      await coordinator.placeCall(
        contactPeerId: 'remote-account',
        localAccountPeerId: 'local-account',
        localDeviceId: 'local-device',
      );
      final runtime = CallSignalingRuntime(
        directCallSignalStream: stream.stream,
        mailboxClient: _Mailbox(),
        handleIncoming: (_) async => IncomingCallSignalOutcome.rejected,
        coordinator: coordinator,
        networkEffectsAllowed: () => true,
      );
      await runtime.start();

      await expectLater(runtime.shutdown(), throwsStateError);

      expect(runtime.isDisposed, isTrue);
      expect(stream.hasListener, isFalse);
      await expectLater(runtime.shutdown(), completes);
    },
  );

  test('a page holding an invite and a terminal for the same call marks the '
      'invite superseded', () async {
    final stream = StreamController<ChatMessage>.broadcast();
    addTearDown(stream.close);
    final mailbox = _Mailbox();
    final coordinator = _coordinator();
    addTearDown(coordinator.dispose);
    final frames = <IncomingCallSignalFrame>[];
    final peeked = <String?>[];
    final callA = CallId.parse('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    final callB = CallId.parse('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
    CallMailboxEvent event(String messageId) => CallMailboxEvent(
      callHandle: 'handle-$messageId',
      messageId: messageId,
      authenticatedSenderDevicePeerId: 'sender-device',
      recipientDevicePeerId: 'recipient-device',
      envelopeJson: '{"type":"call_signal","id":"$messageId"}',
      receiptAtMs: 1,
      expiresAtMs: 2,
    );
    final runtime = CallSignalingRuntime(
      directCallSignalStream: stream.stream,
      mailboxClient: mailbox,
      handleIncoming: (frame) async {
        frames.add(frame);
        return IncomingCallSignalOutcome.accepted;
      },
      peekIncoming: (frame) async {
        peeked.add(frame.expectedMessageId);
        return switch (frame.expectedMessageId) {
          'invite-a' => IncomingCallSignalPeek(
            callId: callA,
            event: CallSignalType.invite,
          ),
          'terminate-a' => IncomingCallSignalPeek(
            callId: callA,
            event: CallSignalType.terminate,
          ),
          'invite-b' => IncomingCallSignalPeek(
            callId: callB,
            event: CallSignalType.invite,
          ),
          _ => null,
        };
      },
      coordinator: coordinator,
      networkEffectsAllowed: () => true,
    );
    addTearDown(runtime.shutdown);
    mailbox.pages.add(
      CallMailboxRetrieveResult(
        events: <CallMailboxEvent>[
          event('invite-a'),
          event('terminate-a'),
          event('invite-b'),
          event('opaque'),
        ],
        receiptAtMs: 1,
        expiresAtMs: 2,
        hasMore: false,
      ),
    );

    await runtime.start();
    await runtime.settle();

    expect(peeked, <String?>['invite-a', 'terminate-a', 'invite-b', 'opaque']);
    expect(frames.map((frame) => frame.expectedMessageId).toList(), <String?>[
      'invite-a',
      'terminate-a',
      'invite-b',
      'opaque',
    ]);
    expect(frames.map((frame) => frame.terminalFollows).toList(), <bool>[
      true,
      false,
      false,
      false,
    ]);
    expect(mailbox.acks, 4);
  });

  test('a single-event page is handled without a peek', () async {
    final stream = StreamController<ChatMessage>.broadcast();
    addTearDown(stream.close);
    final mailbox = _Mailbox();
    final coordinator = _coordinator();
    addTearDown(coordinator.dispose);
    final frames = <IncomingCallSignalFrame>[];
    var peeks = 0;
    final runtime = CallSignalingRuntime(
      directCallSignalStream: stream.stream,
      mailboxClient: mailbox,
      handleIncoming: (frame) async {
        frames.add(frame);
        return IncomingCallSignalOutcome.accepted;
      },
      peekIncoming: (_) async {
        peeks++;
        return null;
      },
      coordinator: coordinator,
      networkEffectsAllowed: () => true,
    );
    addTearDown(runtime.shutdown);
    mailbox.pages.add(
      CallMailboxRetrieveResult(
        events: <CallMailboxEvent>[
          CallMailboxEvent(
            callHandle: 'handle',
            messageId: 'invite',
            authenticatedSenderDevicePeerId: 'sender-device',
            recipientDevicePeerId: 'recipient-device',
            envelopeJson: '{"type":"call_signal"}',
            receiptAtMs: 1,
            expiresAtMs: 2,
          ),
        ],
        receiptAtMs: 1,
        expiresAtMs: 2,
        hasMore: false,
      ),
    );

    await runtime.start();
    await runtime.settle();

    expect(peeks, 0);
    expect(frames.single.terminalFollows, isFalse);
    expect(mailbox.acks, 1);
  });
}
