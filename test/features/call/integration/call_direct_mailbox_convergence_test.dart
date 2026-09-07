import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_control_effect_executor.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/call_signaling_context_store.dart';
import 'package:flutter_app/features/call/application/handle_incoming_call_signal.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/infrastructure/call_mailbox_client.dart';
import 'package:flutter_app/features/call/infrastructure/call_signaling_runtime.dart';
import 'package:flutter_app/features/call/infrastructure/call_trusted_roster_provider.dart';
import 'package:flutter_app/features/call/infrastructure/secure_call_envelope_codec.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

final class _History implements CallHistoryRepository {
  final List<CallHistoryEntry> entries = <CallHistoryEntry>[];

  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async => null;

  @override
  Future<List<CallHistoryEntry>> listForContact(String peerId) async =>
      const <CallHistoryEntry>[];

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {
    entries.add(entry);
  }
}

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
  }) async =>
      signature ==
      base64Encode(utf8.encode('$senderSigningPublicKey:$canonicalData'));
}

final class _Roster implements CallTrustedRosterProvider {
  const _Roster();

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

final class _Presenter implements IncomingCallPresenter {
  int presentations = 0;

  @override
  Future<bool> present(IncomingCallPresentation presentation) async {
    presentations++;
    return true;
  }

  @override
  Future<void> dismiss(IncomingCallPresentation presentation) async {}
}

final class _NativeLifecycle implements ProvisionalNativeIncomingCallLifecycle {
  final List<String> cancelledHandles = <String>[];

  @override
  Future<void> remoteCancel(String callHandle) async {
    cancelledHandles.add(callHandle);
  }

  @override
  Future<void> authenticationFailed(String callHandle) async {}

  @override
  Future<void> expire(String callHandle) async {}

  @override
  Future<void> revokeOpaqueContact(String callHandle) async {}

  @override
  Future<void> updateAuthenticatedContact({
    required String callHandle,
    required String displayName,
  }) async {}
}

final class _Mailbox implements CallMailboxClient {
  _Mailbox(this.page);

  CallMailboxRetrieveResult? page;
  int acked = 0;
  int cancelCalls = 0;
  int retrieveCalls = 0;
  int storeCalls = 0;
  final Set<String> _cancelledHandles = <String>{};

  @override
  Future<CallMailboxRetrieveResult> retrieve({
    String? callHandle,
    int limit = 64,
  }) async {
    retrieveCalls++;
    final current = page;
    page = null;
    return current ??
        CallMailboxRetrieveResult(
          events: const <CallMailboxEvent>[],
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
    acked += messageIds.length;
    return messageIds.length;
  }

  @override
  Future<bool> cancel({
    required String recipientDevicePeerId,
    required String callHandle,
  }) {
    cancelCalls++;
    _cancelledHandles.add(callHandle);
    final current = page;
    if (current != null) {
      page = CallMailboxRetrieveResult(
        events: current.events
            .where((event) => event.callHandle != callHandle)
            .toList(growable: false),
        receiptAtMs: current.receiptAtMs,
        expiresAtMs: current.expiresAtMs,
        hasMore: false,
      );
    }
    return Future<bool>.value(true);
  }

  @override
  Future<CallMailboxStoreResult> store(CallMailboxStoreRequest request) async {
    storeCalls++;
    if (!_cancelledHandles.contains(request.callHandle)) {
      // The relay appends: every stored event of the call stays retrievable
      // behind the earlier ones.
      page = CallMailboxRetrieveResult(
        events: <CallMailboxEvent>[
          ...?page?.events,
          CallMailboxEvent(
            callHandle: request.callHandle,
            messageId: request.messageId,
            authenticatedSenderDevicePeerId: 'sender-device',
            recipientDevicePeerId: request.recipientDevicePeerId,
            envelopeJson: request.envelopeJson,
            receiptAtMs: 1,
            expiresAtMs: request.expiresAtMs,
          ),
        ],
        receiptAtMs: 1,
        expiresAtMs: request.expiresAtMs,
        hasMore: false,
      );
    }
    return CallMailboxStoreResult(
      status: CallMailboxStoreStatus.stored,
      receiptAtMs: 1,
      expiresAtMs: request.expiresAtMs,
      eventCount: 1,
      totalBytes: request.envelopeJson.length,
      pendingHandles: 1,
    );
  }
}

final class _MailboxBackedControlPort implements CallControlSignalingPort {
  const _MailboxBackedControlPort({
    required this.mailbox,
    required this.codec,
    required this.callHandle,
  });

  final _Mailbox mailbox;
  final SecureCallEnvelopeCodec codec;
  final String callHandle;

  @override
  Future<OutgoingCallSignalingPreparation> prepareOutgoingInvite(
    CallSessionSnapshot snapshot,
  ) async => OutgoingCallSignalingPreparation(
    callHandle: callHandle,
    remoteAccountPeerId: 'recipient-account',
    remoteDevicePeerId: 'recipient-device',
  );

  @override
  Future<CallControlSendResult> send({
    required CallSignal signal,
    required String callHandle,
  }) async {
    // Every pre-connect control signal, the caller's terminate included, is
    // stored behind the invite: that mirrors the production port.
    final envelope = await codec.encode(
      signal: signal,
      callHandle: callHandle,
      recipientMlKemPublicKey: 'recipient-mlkem-public',
      senderSigningPrivateKey: 'sender-signing-key',
    );
    await mailbox.store(
      CallMailboxStoreRequest(
        recipientDevicePeerId: signal.recipientDevicePeerId,
        callHandle: callHandle,
        messageId: signal.messageId,
        envelopeJson: envelope,
        expiresAtMs: signal.expiresAtMs,
        wakeHandle: 'opaque-wake-handle',
      ),
    );
    return CallControlSendResult(
      directAccepted: false,
      mailboxStored: true,
      mailboxStoreSettled: Future<void>.value(),
    );
  }
}

void main() {
  for (final route in <CallRouteClass>[
    CallRouteClass.direct,
    CallRouteClass.ephemeralMailbox,
  ]) {
    test('${route.name} old-generation hang-up ends a reconnecting caller '
        'and cleans up exactly once', () async {
      final now = DateTime.utc(2026, 8, 30, 12);
      final nowMs = now.millisecondsSinceEpoch;
      final callId = CallId.parse('22222222-2222-4222-8222-222222222222');
      const handle = '33333333-3333-4333-8333-333333333333';
      final codec = SecureCallEnvelopeCodec(
        crypto: _Crypto(),
        nowMs: () => nowMs,
      );
      final context = CallSignalingContextStore();
      final native = _NativeLifecycle();
      final history = _History();
      final cleaned = <CallSessionSnapshot>[];
      final caller = CallCoordinator(
        reducer: const CallReducer(),
        cleanupCoordinator: CallCleanupCoordinator(<CallCleanupStep>[
          CallCleanupStep('call_resources', (snapshot) async {
            cleaned.add(snapshot);
            context.purge(snapshot.callId!);
          }, requiredForTerminalAck: true),
        ]),
        historyProjector: CallHistoryProjector(history),
        clock: () => now,
        idSource: () => callId,
      );
      addTearDown(caller.dispose);
      final handler = HandleIncomingCallSignal(
        codec: codec,
        coordinator: caller,
        trustedRosterProvider: const _Roster(),
        localAuthorityProvider: () async => const CallLocalDeviceAuthority(
          accountPeerId: 'recipient-account',
          devicePeerId: 'recipient-device',
          mlKemSecretKey: 'recipient-mlkem-secret',
        ),
        incomingCallPresenter: _Presenter(),
        networkEffectsAllowed: () => true,
        signalingContextObserver: context,
        provisionalNativeLifecycle: native,
      );
      Future<IncomingCallSignalFrame> frame(CallSignalType event) async {
        final signal = CallSignal.create(
          callId: callId,
          messageId: event == CallSignalType.accept
              ? '11111111-1111-4111-8111-111111111111'
              : '44444444-4444-4444-8444-444444444444',
          event: event,
          senderAccountPeerId: 'sender-account',
          senderDevicePeerId: 'sender-device',
          recipientAccountPeerId: 'recipient-account',
          recipientDevicePeerId: 'recipient-device',
          senderSequence: event == CallSignalType.accept ? 1 : 2,
          iceGeneration: 0,
          createdAtMs: nowMs,
          expiresAtMs: nowMs + 45_000,
          payload: event == CallSignalType.terminate
              ? const <String, Object?>{'reason': 'local_hangup'}
              : const <String, Object?>{},
        );
        return IncomingCallSignalFrame(
          envelopeJson: await codec.encode(
            signal: signal,
            callHandle: handle,
            recipientMlKemPublicKey: 'recipient-mlkem-public',
            senderSigningPrivateKey: 'sender-signing-key',
          ),
          authenticatedTransportPeerId: 'sender-device',
          route: route,
          expectedCallHandle: handle,
          expectedMessageId: signal.messageId,
          expectedExpiresAtMs: signal.expiresAtMs,
          expectedRecipientDevicePeerId: 'recipient-device',
        );
      }

      await caller.placeCall(
        contactPeerId: 'sender-account',
        localAccountPeerId: 'recipient-account',
        localDeviceId: 'recipient-device',
      );
      context.storeOutgoing(
        callId: callId,
        callHandle: handle,
        localAccountPeerId: 'recipient-account',
        localDevicePeerId: 'recipient-device',
        remoteAccountPeerId: 'sender-account',
        remoteDevicePeerId: 'sender-device',
      );
      Future<void> dispatch(CallEventType type) async {
        final result = await caller.dispatch(
          CallEvent(
            type: type,
            eventId: type.name,
            occurredAt: now,
            callId: callId,
          ),
        );
        expect(result.decision, CallEventDecision.applied);
      }

      await dispatch(CallEventType.outgoingInviteReady);
      expect(
        await handler.handle(await frame(CallSignalType.accept)),
        IncomingCallSignalOutcome.accepted,
      );
      await dispatch(CallEventType.negotiationReady);
      await dispatch(CallEventType.mediaConnected);
      await dispatch(CallEventType.mediaLost);
      // The local caller has reserved restart generation 1, but the receiver
      // hangs up at generation 0 before the restart announcement reaches it.
      context.reserveNextMetadata(callId, iceGeneration: 1);
      expect(caller.activeSession?.state, CallState.reconnecting);

      final terminate = await frame(CallSignalType.terminate);
      expect(
        await handler.handle(terminate),
        IncomingCallSignalOutcome.accepted,
      );
      expect(caller.activeSession, isNull);
      expect(native.cancelledHandles, <String>[handle]);
      expect(cleaned, hasLength(1));
      expect(cleaned.single.endReason, CallEndReason.localHangup);
      expect(context.read(callId), isNull);
      expect(caller.terminalCleanupAckReady(callId), isTrue);
      expect(history.entries.single.terminalReason, CallEndReason.localHangup);

      expect(
        await handler.handle(terminate),
        IncomingCallSignalOutcome.duplicate,
      );
      expect(native.cancelledHandles, <String>[handle]);
      expect(cleaned, hasLength(1));
      expect(history.entries, hasLength(1));
    });
  }

  test(
    'authenticated direct and mailbox duplicate converge on one session and UI',
    () async {
      final now = DateTime.utc(2026, 8, 30, 12);
      final nowMs = now.millisecondsSinceEpoch;
      const callHandle = '33333333-3333-4333-8333-333333333333';
      final signal = CallSignal.create(
        callId: CallId.parse('22222222-2222-4222-8222-222222222222'),
        messageId: '11111111-1111-4111-8111-111111111111',
        event: CallSignalType.invite,
        senderAccountPeerId: 'sender-account',
        senderDevicePeerId: 'sender-device',
        recipientAccountPeerId: 'recipient-account',
        recipientDevicePeerId: 'recipient-device',
        senderSequence: 1,
        iceGeneration: 0,
        createdAtMs: nowMs,
        expiresAtMs: nowMs + 45_000,
        payload: const <String, Object?>{},
      );
      final codec = SecureCallEnvelopeCodec(
        crypto: _Crypto(),
        nowMs: () => nowMs,
      );
      final envelope = await codec.encode(
        signal: signal,
        callHandle: callHandle,
        recipientMlKemPublicKey: 'recipient-mlkem-public',
        senderSigningPrivateKey: 'sender-signing-key',
      );
      final mailbox = _Mailbox(
        CallMailboxRetrieveResult(
          events: <CallMailboxEvent>[
            CallMailboxEvent(
              callHandle: callHandle,
              messageId: signal.messageId,
              authenticatedSenderDevicePeerId: 'sender-device',
              recipientDevicePeerId: 'recipient-device',
              envelopeJson: envelope,
              receiptAtMs: nowMs,
              expiresAtMs: signal.expiresAtMs,
            ),
          ],
          receiptAtMs: nowMs,
          expiresAtMs: signal.expiresAtMs,
          hasMore: false,
        ),
      );
      final coordinator = CallCoordinator(
        reducer: const CallReducer(),
        cleanupCoordinator: CallCleanupCoordinator(const <CallCleanupStep>[]),
        historyProjector: CallHistoryProjector(_History()),
        clock: () => now,
        idSource: () => signal.callId,
      );
      final presenter = _Presenter();
      final handler = HandleIncomingCallSignal(
        codec: codec,
        coordinator: coordinator,
        trustedRosterProvider: const _Roster(),
        localAuthorityProvider: () async => const CallLocalDeviceAuthority(
          accountPeerId: 'recipient-account',
          devicePeerId: 'recipient-device',
          mlKemSecretKey: 'recipient-mlkem-secret',
        ),
        incomingCallPresenter: presenter,
        networkEffectsAllowed: () => true,
      );
      final direct = StreamController<ChatMessage>.broadcast();
      final runtime = CallSignalingRuntime(
        directCallSignalStream: direct.stream,
        mailboxClient: mailbox,
        handleIncoming: handler.handle,
        coordinator: coordinator,
        networkEffectsAllowed: () => true,
      );
      addTearDown(runtime.shutdown);
      addTearDown(direct.close);

      await runtime.start();
      direct.add(
        ChatMessage(
          from: 'sender-device',
          to: 'recipient-device',
          content: envelope,
          timestamp: now.toIso8601String(),
          isIncoming: true,
          transport: 'direct',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await runtime.settle();

      expect(coordinator.activeSession?.state, CallState.ringing);
      expect(presenter.presentations, 1);

      await runtime.onResume();

      expect(coordinator.activeSession?.callId, signal.callId);
      expect(coordinator.activeSession?.state, CallState.ringing);
      expect(presenter.presentations, 1);
      expect(mailbox.acked, 1);
    },
  );

  test('caller cancellation stores its terminate behind the invite so a late '
      'recipient drain never rings', () async {
    final now = DateTime.utc(2026, 8, 30, 12);
    final nowMs = now.millisecondsSinceEpoch;
    final callId = CallId.parse('22222222-2222-4222-8222-222222222222');
    const callHandle = '33333333-3333-4333-8333-333333333333';
    final codec = SecureCallEnvelopeCodec(
      crypto: _Crypto(),
      nowMs: () => nowMs,
    );
    final mailbox = _Mailbox(null);
    final senderContext = CallSignalingContextStore();
    late final CallControlEffectExecutor senderControl;
    final sender = CallCoordinator(
      reducer: const CallReducer(),
      cleanupCoordinator: CallCleanupCoordinator(<CallCleanupStep>[
        CallCleanupStep('call_signaling_context', (snapshot) async {
          await senderControl.retireOutgoingPreconnectInvite(snapshot);
          senderContext.purge(snapshot.callId!);
        }, requiredForTerminalAck: true),
      ]),
      historyProjector: CallHistoryProjector(_History()),
      effectExecutor: senderControl = CallControlEffectExecutor(
        contextStore: senderContext,
        signalingPort: _MailboxBackedControlPort(
          mailbox: mailbox,
          codec: codec,
          callHandle: callHandle,
        ),
        clock: () => now,
        idSource: () => CallId.parse('11111111-1111-4111-8111-111111111111'),
        cancelOutgoingMailboxInvite:
            ({required recipientDevicePeerId, required callHandle}) =>
                mailbox.cancel(
                  recipientDevicePeerId: recipientDevicePeerId,
                  callHandle: callHandle,
                ),
      ),
      clock: () => now,
      idSource: () => callId,
    );
    addTearDown(sender.dispose);

    await sender.placeCall(
      contactPeerId: 'recipient-account',
      localAccountPeerId: 'sender-account',
      localDeviceId: 'sender-device',
    );
    expect(mailbox.storeCalls, 1);
    await sender.dispatch(
      CallEvent(
        type: CallEventType.cancel,
        eventId: 'caller-cancel',
        occurredAt: now,
        callId: callId,
        contactPeerId: 'recipient-account',
      ),
    );

    final recipient = CallCoordinator(
      reducer: const CallReducer(),
      cleanupCoordinator: CallCleanupCoordinator(const <CallCleanupStep>[]),
      historyProjector: CallHistoryProjector(_History()),
      clock: () => now,
      idSource: () => callId,
    );
    final presenter = _Presenter();
    final emittedStates = <CallState>[];
    final stateSubscription = recipient.snapshots.listen(
      (snapshot) => emittedStates.add(snapshot.state),
    );
    addTearDown(stateSubscription.cancel);
    final handler = HandleIncomingCallSignal(
      codec: codec,
      coordinator: recipient,
      trustedRosterProvider: const _Roster(),
      localAuthorityProvider: () async => const CallLocalDeviceAuthority(
        accountPeerId: 'recipient-account',
        devicePeerId: 'recipient-device',
        mlKemSecretKey: 'recipient-mlkem-secret',
      ),
      incomingCallPresenter: presenter,
      networkEffectsAllowed: () => true,
    );
    final direct = StreamController<ChatMessage>.broadcast();
    final outcomes = <IncomingCallSignalOutcome>[];
    final runtime = CallSignalingRuntime(
      directCallSignalStream: direct.stream,
      mailboxClient: mailbox,
      handleIncoming: (frame) async {
        final outcome = await handler.handle(frame);
        outcomes.add(outcome);
        return outcome;
      },
      peekIncoming: handler.peek,
      coordinator: recipient,
      networkEffectsAllowed: () => true,
    );
    addTearDown(runtime.shutdown);
    addTearDown(direct.close);

    expect(await runtime.start(), isTrue);
    await runtime.settle();

    // The invite stays for the callee the relay may already have woken;
    // the terminate behind it is that callee's only cancel.
    expect(mailbox.cancelCalls, 0);
    expect(mailbox.storeCalls, 2);
    expect(mailbox.retrieveCalls, 1);
    expect(mailbox.acked, 2);
    // The invite is superseded by the terminate behind it; the terminate
    // itself is consumed, never left for a replay.
    expect(outcomes, hasLength(2));
    expect(outcomes.first, IncomingCallSignalOutcome.superseded);
    expect(outcomes.last, isNot(IncomingCallSignalOutcome.deferred));
    expect(presenter.presentations, 0);
    expect(emittedStates, isNot(contains(CallState.ringing)));
    expect(recipient.activeSession, isNull);
    expect(senderContext.read(callId), isNull);
    expect(sender.terminalCleanupAckReady(callId), isTrue);
  });
}
