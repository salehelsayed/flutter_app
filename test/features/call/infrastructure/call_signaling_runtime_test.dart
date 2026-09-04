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
import 'package:flutter_app/features/call/domain/call_state.dart';
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

CallCoordinator _coordinator() => CallCoordinator(
  reducer: const CallReducer(),
  cleanupCoordinator: CallCleanupCoordinator(const <CallCleanupStep>[]),
  historyProjector: CallHistoryProjector(_History()),
  clock: () => DateTime.utc(2026, 8, 30),
  idSource: () => CallId.parse('11111111-1111-4111-8111-111111111111'),
);

final class _Mailbox implements CallMailboxClient {
  final List<CallMailboxRetrieveResult> pages = <CallMailboxRetrieveResult>[];
  int retrieves = 0;
  int acks = 0;
  int ackAttempts = 0;
  bool failAcks = false;
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
    if (failAcks) throw StateError('temporary mailbox failure');
    acks += messageIds.length;
    return messageIds.length;
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
}) async {
  final coordinator = _coordinator();
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

void main() {
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
}
