import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/call_signaling_context_store.dart';
import 'package:flutter_app/features/call/application/handle_incoming_call_signal.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/domain/call_signal_v2.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/domain/call_wire_signal.dart';
import 'package:flutter_app/features/call/infrastructure/call_trusted_roster_provider.dart';
import 'package:flutter_app/features/call/infrastructure/call_mailbox_client.dart';
import 'package:flutter_app/features/call/infrastructure/call_signaling_runtime.dart';
import 'package:flutter_app/features/call/infrastructure/secure_call_envelope_codec.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

const _nowMs = 2000000;
const _callHandle = '33333333-3333-4333-8333-333333333333';
const _negotiationId = '44444444-4444-4444-8444-444444444444';
const _switchId = '55555555-5555-4555-8555-555555555555';
final _callId = CallId.parse('22222222-2222-4222-8222-222222222222');
final _otherCall = CallId.parse('77777777-7777-4777-8777-777777777777');

final class _Crypto implements CallEnvelopeCrypto {
  bool throwOnVerify = false;
  bool throwOnDecrypt = false;

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

final class _Roster implements CallTrustedRosterProvider {
  const _Roster();

  @override
  Future<CallTrustedRosterSnapshot> loadForContact(String peerId) async =>
      throw UnimplementedError();

  @override
  Future<TrustedCallDeviceAuthority?> resolveAuthenticatedTransport(
    String transportPeerId,
  ) async => const {'sender-device', 'other-device'}.contains(transportPeerId)
      ? TrustedCallDeviceAuthority(
          accountPeerId: 'sender-account',
          devicePeerId: transportPeerId,
          linked: true,
          deviceKeyEpoch: 1,
          signingPublicKey: 'sender-signing-key',
          mlKemPublicKey: 'sender-mlkem-key',
        )
      : null;
}

final class _History implements CallHistoryRepository {
  final Map<CallId, CallHistoryEntry> entries = <CallId, CallHistoryEntry>{};

  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async => entries[callId];

  @override
  Future<List<CallHistoryEntry>> listForContact(String peerId) async =>
      const [];

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {
    entries.putIfAbsent(entry.callId, () => entry);
  }
}

final class _Effects implements CallEffectExecutor {
  final effects = <CallEffectType>[];

  @override
  Future<CallEvent?> execute(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) async {
    effects.add(effect.type);
    return null;
  }
}

final class _Presenter implements IncomingCallPresenter {
  int calls = 0;
  int dismissals = 0;
  Completer<bool>? gate;
  final started = Completer<void>();

  @override
  Future<bool> present(IncomingCallPresentation presentation) async {
    calls++;
    if (!started.isCompleted) started.complete();
    return gate == null ? true : gate!.future;
  }

  @override
  Future<void> dismiss(IncomingCallPresentation presentation) async {
    dismissals++;
  }
}

final class _Native implements ProvisionalNativeIncomingCallLifecycle {
  int cancelled = 0;
  void Function()? onCancel;
  Completer<void>? cancelGate;
  final cancelStarted = Completer<void>();

  @override
  Future<void> remoteCancel(String callHandle) async {
    cancelled++;
    onCancel?.call();
    if (!cancelStarted.isCompleted) cancelStarted.complete();
    await cancelGate?.future;
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

final class _LegacyObserver
    implements AuthenticatedCallSignalingContextObserver {
  int captured = 0;

  @override
  void captureAuthenticated({
    required CallSignal signal,
    required String callHandle,
    CallAdmissionAuthorityWitness? admissionAuthority,
  }) {
    captured++;
  }

  @override
  void purge(CallId callId) {}
}

CallSignalV2 _v2({
  String event = 'invite',
  int sequence = 1,
  CallId? callId,
  String media = 'video',
  bool outgoing = false,
  String senderDevice = 'sender-device',
  Map<String, Object?>? payload,
}) => CallSignalV2.fromMap({
  'schema': CallSignalV2.schema,
  'call_id': (callId ?? _callId).value,
  'message_id':
      'aaaaaaaa-aaaa-4aaa-8aaa-${sequence.toRadixString(16).padLeft(12, '0')}',
  'event': event,
  'sender_account_peer_id': outgoing ? 'recipient-account' : 'sender-account',
  'sender_device_peer_id': outgoing ? 'recipient-device' : senderDevice,
  'recipient_account_peer_id': outgoing
      ? 'sender-account'
      : 'recipient-account',
  'recipient_device_peer_id': outgoing ? 'sender-device' : 'recipient-device',
  'sender_sequence': sequence,
  'ice_generation': 0,
  'created_at_ms': _nowMs,
  'expires_at_ms': _nowMs + 45000,
  'payload':
      payload ??
      switch (event) {
        'invite' => {
          'media': media,
          'camera': 'off',
          'capabilities': ['audio', 'video'],
        },
        'accept' => {'media': media, 'camera': 'off'},
        'reject' || 'terminate' => {'reason': 'unsupported'},
        'offer' || 'answer' => {
          'negotiation_id': _negotiationId,
          'purpose': 'initial',
          'switch_id': null,
          'media_revision': 0,
          'media': media,
          'description': 'private-sdp',
          'fingerprint': 'private-fingerprint',
        },
        'ice' => {
          'negotiation_id': _negotiationId,
          'candidate': 'private-candidate',
          'media_id': null,
          'media_line_index': null,
        },
        'ice_restart' => {
          'negotiation_id': _negotiationId,
          'media_revision': 0,
        },
        'media_request' => {
          'switch_id': _switchId,
          'base_revision': 0,
          'target_media': 'video',
          'camera': 'off',
        },
        'media_response' => {
          'switch_id': _switchId,
          'base_revision': 0,
          'decision': 'accept',
          'camera': 'off',
        },
        'media_commit' || 'media_commit_ack' => {
          'switch_id': _switchId,
          'media_revision': 1,
          'media': 'video',
        },
        'media_abort' => {
          'switch_id': _switchId,
          'base_revision': 0,
          'media_revision': 1,
          'media': 'audio',
          'reason': 'timeout',
        },
        'camera_state' => {'media_revision': 0, 'state': 'on'},
        _ => <String, Object?>{},
      },
}, videoEnabled: true);

CallSignal _v1Invite() => CallSignal.create(
  callId: _callId,
  messageId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  event: CallSignalType.invite,
  senderAccountPeerId: 'sender-account',
  senderDevicePeerId: 'sender-device',
  recipientAccountPeerId: 'recipient-account',
  recipientDevicePeerId: 'recipient-device',
  senderSequence: 1,
  iceGeneration: 0,
  createdAtMs: _nowMs,
  expiresAtMs: _nowMs + 45000,
  payload: const {
    'capabilities': ['audio'],
    'metadata': {'media': 'audio', 'video': false},
  },
);

CallSignal _v1Terminal({
  int sequence = 2,
  String reason = 'caller_cancelled',
}) => CallSignal.create(
  callId: _callId,
  messageId:
      'cccccccc-cccc-4ccc-8ccc-${sequence.toRadixString(16).padLeft(12, '0')}',
  event: CallSignalType.terminate,
  senderAccountPeerId: 'sender-account',
  senderDevicePeerId: 'sender-device',
  recipientAccountPeerId: 'recipient-account',
  recipientDevicePeerId: 'recipient-device',
  senderSequence: sequence,
  iceGeneration: 0,
  createdAtMs: _nowMs,
  expiresAtMs: _nowMs + 45000,
  payload: {'reason': reason},
);

final class _MailboxPage implements CallMailboxClient {
  final events = <CallMailboxEvent>[];
  final frames = <IncomingCallSignalFrame>[];
  final outcomes = <IncomingCallSignalOutcome>[];
  final acknowledged = <String>[];
  final settled = <CallWireSignal>[];

  @override
  Future<CallMailboxRetrieveResult> retrieve({
    String? callHandle,
    int limit = 64,
  }) async {
    final page = List<CallMailboxEvent>.of(events);
    events.clear();
    return CallMailboxRetrieveResult(
      events: page,
      receiptAtMs: _nowMs,
      expiresAtMs: _nowMs + 45000,
      hasMore: false,
    );
  }

  @override
  Future<int> ack({
    required String callHandle,
    required List<String> messageIds,
  }) async {
    acknowledged.addAll(messageIds);
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

final class _Harness {
  _Harness({
    bool videoEnabled = true,
    int contextCapacity = 4,
    AuthenticatedCallSignalingContextObserver? observer,
    AuthenticatedIncomingCallV2MediaHandler? onMedia,
  }) {
    contexts = CallSignalingContextStore(
      videoEnabled: true,
      maxContexts: contextCapacity,
    );
    coordinator = CallCoordinator(
      reducer: const CallReducer(),
      cleanupCoordinator: CallCleanupCoordinator(const <CallCleanupStep>[]),
      historyProjector: CallHistoryProjector(_History()),
      effectExecutor: effects,
      clock: () => DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true),
      idSource: () => _callId,
    );
    codec = SecureCallEnvelopeCodec(
      crypto: _Crypto(),
      nowMs: () => nowMs,
      videoEnabled: true,
    );
    handler = HandleIncomingCallSignal(
      codec: codec,
      coordinator: coordinator,
      trustedRosterProvider: const _Roster(),
      localAuthorityProvider: () async => const CallLocalDeviceAuthority(
        accountPeerId: 'recipient-account',
        devicePeerId: 'recipient-device',
        mlKemSecretKey: 'recipient-mlkem-secret-key',
      ),
      incomingCallPresenter: presenter,
      provisionalNativeLifecycle: native,
      networkEffectsAllowed: () => networkAllowed,
      signalingContextObserver: observer ?? contexts,
      videoEnabled: videoEnabled,
      incomingV2MediaHandler: onMedia,
    );
    addTearDown(coordinator.dispose);
  }

  int nowMs = _nowMs;
  bool networkAllowed = true;
  final effects = _Effects();
  final presenter = _Presenter();
  final native = _Native();
  late final CallCoordinator coordinator;
  late final CallSignalingContextStore contexts;
  late final SecureCallEnvelopeCodec codec;
  late final HandleIncomingCallSignal handler;

  Future<IncomingCallSignalFrame> frame(
    CallWireSignal signal, {
    bool mailbox = false,
    String callHandle = _callHandle,
    bool terminalFollows = false,
    String? expectedMessageId,
  }) async {
    final envelope = signal is CallSignalV2
        ? await codec.encodeV2(
            signal: signal,
            callHandle: callHandle,
            recipientMlKemPublicKey: 'recipient-mlkem-key',
            senderSigningPrivateKey: 'sender-signing-key',
          )
        : await codec.encode(
            signal: signal as CallSignal,
            callHandle: callHandle,
            recipientMlKemPublicKey: 'recipient-mlkem-key',
            senderSigningPrivateKey: 'sender-signing-key',
          );
    return IncomingCallSignalFrame(
      envelopeJson: envelope,
      authenticatedTransportPeerId: signal.senderDevicePeerId,
      route: mailbox ? CallRouteClass.ephemeralMailbox : CallRouteClass.direct,
      expectedCallHandle: mailbox ? callHandle : null,
      expectedMessageId:
          expectedMessageId ?? (mailbox ? signal.messageId : null),
      expectedExpiresAtMs: mailbox ? signal.expiresAtMs : null,
      expectedRecipientDevicePeerId: mailbox
          ? signal.recipientDevicePeerId
          : null,
      terminalFollows: terminalFollows,
    );
  }

  Future<IncomingCallSignalOutcome> receive(CallWireSignal signal) async =>
      handler.handle(await frame(signal));

  Future<void> admitIncoming() async {
    expect(await receive(_v2()), IncomingCallSignalOutcome.accepted);
  }

  Future<_MailboxPage> drainPage(
    List<({CallWireSignal signal, String handle})> rows,
  ) async {
    final mailbox = _MailboxPage();
    for (final row in rows) {
      final incoming = await frame(
        row.signal,
        mailbox: true,
        callHandle: row.handle,
      );
      mailbox.events.add(
        CallMailboxEvent(
          callHandle: row.handle,
          messageId: row.signal.messageId,
          authenticatedSenderDevicePeerId: row.signal.senderDevicePeerId,
          recipientDevicePeerId: row.signal.recipientDevicePeerId,
          envelopeJson: incoming.envelopeJson,
          receiptAtMs: nowMs,
          expiresAtMs: row.signal.expiresAtMs,
        ),
      );
    }
    final runtime = CallSignalingRuntime(
      directCallSignalStream: const Stream<ChatMessage>.empty(),
      mailboxClient: mailbox,
      handleIncoming: handler.handle,
      handleMailboxIncoming: (frame) async {
        mailbox.frames.add(frame);
        final result = await handler.handleMailbox(frame);
        mailbox.outcomes.add(result.outcome);
        return result;
      },
      peekIncoming: handler.peek,
      prepareMailboxSettlement: (_) async =>
          (terminal, {required canApply}) async {
            expect(canApply(), isTrue);
            expect(
              mailbox.acknowledged,
              contains(terminal.signal.messageId),
              reason: 'Native settlement must remain after exact row ACK.',
            );
            mailbox.settled.add(terminal.signal);
          },
      coordinator: coordinator,
      networkEffectsAllowed: () => networkAllowed,
      readCallHandle: (callId) => contexts.read(callId)?.callHandle,
    );
    addTearDown(runtime.shutdown);
    expect(await runtime.start(), isTrue);
    await runtime.settle();
    return mailbox;
  }

  Future<void> outgoing() async {
    contexts.storeOutgoingV2(
      invite: _v2(outgoing: true),
      callHandle: _callHandle,
    );
    await coordinator.dispatch(
      CallEvent(
        type: CallEventType.place,
        eventId: 'place',
        callId: _callId,
        occurredAt: DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true),
        contactPeerId: 'sender-account',
        localAccountPeerId: 'recipient-account',
        localDeviceId: 'recipient-device',
        remoteAccountPeerId: 'sender-account',
        remoteDeviceId: 'sender-device',
      ),
    );
    await coordinator.dispatch(
      CallEvent(
        type: CallEventType.outgoingInviteReady,
        eventId: 'ready',
        callId: _callId,
        occurredAt: DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true),
        contactPeerId: 'sender-account',
      ),
    );
  }
}

void main() {
  test(
    'U3F-VERSION-1 ordinary v1 terminal cannot suppress a v2 page invite',
    () async {
      final h = _Harness();
      final invite = _v2();
      final page = await h.drainPage([
        (signal: invite, handle: _callHandle),
        (signal: _v1Terminal(), handle: _callHandle),
      ]);
      expect(page.frames.first.terminalFollows, isFalse);
      expect(page.outcomes, [
        IncomingCallSignalOutcome.accepted,
        IncomingCallSignalOutcome.deferred,
      ]);
      expect(h.presenter.calls, 1);
      expect(h.coordinator.activeSession!.state, CallState.ringing);
      expect(h.contexts.read(_callId)!.wireVersion, CallWireVersion.v2);
      expect(h.native.cancelled, 0);
      expect(page.settled, isEmpty);
      expect(page.acknowledged, [invite.messageId]);
    },
  );

  test(
    'U3F-VERSION-1 matching v2 terminal still supersedes without ringing',
    () async {
      final h = _Harness();
      final invite = _v2();
      final terminal = _v2(event: 'terminate', sequence: 2);
      final page = await h.drainPage([
        (signal: invite, handle: _callHandle),
        (signal: terminal, handle: _callHandle),
      ]);
      expect(page.frames.first.terminalFollows, isTrue);
      expect(page.outcomes, [
        IncomingCallSignalOutcome.superseded,
        IncomingCallSignalOutcome.accepted,
      ]);
      expect(h.presenter.calls, 0);
      expect(h.coordinator.isTerminalCall(_callId), isTrue);
      expect(h.native.cancelled, 1);
      expect(page.acknowledged, [invite.messageId, terminal.messageId]);
      expect(page.settled.single.toMap(), terminal.toMap());
    },
  );

  test(
    'U3F-VERSION-1 unsupported cross-version cleanup uses the bound normal path',
    () async {
      final h = _Harness();
      final terminal = _v1Terminal(reason: 'unsupported');
      final page = await h.drainPage([
        (signal: _v2(), handle: _callHandle),
        (signal: terminal, handle: _callHandle),
      ]);
      expect(page.frames.first.terminalFollows, isFalse);
      expect(page.outcomes, [
        IncomingCallSignalOutcome.accepted,
        IncomingCallSignalOutcome.accepted,
      ]);
      expect(h.presenter.calls, 1);
      expect(h.coordinator.isTerminalCall(_callId), isTrue);
      expect(h.contexts.read(_callId), isNull);
      expect(h.native.cancelled, 1);
      expect(page.settled.single.toMap(), terminal.toMap());
    },
  );

  for (final initialOfferReceived in [false, true]) {
    test(
      'U3F-VERSION-1 accepted cleanup scope initialOffer=$initialOfferReceived',
      () async {
        final h = _Harness(
          onMedia:
              ({required signal, required callHandle, required canApply}) =>
                  IncomingCallSignalOutcome.accepted,
        );
        await h.admitIncoming();
        h.contexts.recordLocalAcceptance(_callId, media: CallMediaKind.video);
        final answer = await h.coordinator.dispatch(
          CallEvent(
            type: CallEventType.answer,
            eventId: 'local-answer',
            callId: _callId,
            occurredAt: DateTime.fromMillisecondsSinceEpoch(
              _nowMs,
              isUtc: true,
            ),
          ),
        );
        expect(answer.decision, CallEventDecision.applied);
        if (initialOfferReceived) {
          expect(
            await h.receive(_v2(event: 'offer', sequence: 2)),
            IncomingCallSignalOutcome.accepted,
          );
        }
        expect(
          h.contexts.read(_callId)!.initialOfferReceived,
          initialOfferReceived,
        );
        final terminal = _v1Terminal(reason: 'unsupported', sequence: 3);
        final page = await h.drainPage([
          (signal: terminal, handle: _callHandle),
        ]);
        expect(
          page.outcomes.single,
          initialOfferReceived
              ? IncomingCallSignalOutcome.deferred
              : IncomingCallSignalOutcome.accepted,
        );
        expect(h.coordinator.isTerminalCall(_callId), !initialOfferReceived);
        expect(h.native.cancelled, initialOfferReceived ? 0 : 1);
        expect(page.settled.length, initialOfferReceived ? 0 : 1);
        if (initialOfferReceived) {
          expect(h.contexts.read(_callId)!.wireVersion, CallWireVersion.v2);
          expect(page.acknowledged, isEmpty);
        }
      },
    );
  }

  for (final mismatch in ['handle', 'sender_device']) {
    test(
      'U3F-VERSION-1 $mismatch mismatch cannot suppress the real invite',
      () async {
        final h = _Harness();
        final invite = _v2();
        final page = await h.drainPage([
          (signal: invite, handle: _callHandle),
          (
            signal: _v2(
              event: 'terminate',
              sequence: 2,
              senderDevice: mismatch == 'sender_device'
                  ? 'other-device'
                  : 'sender-device',
            ),
            handle: mismatch == 'handle'
                ? '88888888-8888-4888-8888-888888888888'
                : _callHandle,
          ),
        ]);
        expect(page.frames.first.terminalFollows, isFalse);
        expect(page.outcomes, [
          IncomingCallSignalOutcome.accepted,
          IncomingCallSignalOutcome.rejected,
        ]);
        expect(h.presenter.calls, 1);
        expect(h.coordinator.activeSession!.state, CallState.ringing);
        expect(h.contexts.read(_callId)!.callHandle, _callHandle);
        expect(h.contexts.read(_callId)!.remoteDevicePeerId, 'sender-device');
        expect(h.native.cancelled, 0);
        expect(page.settled, isEmpty);
      },
    );
  }

  test(
    'U3F-VERSION-1 v2 terminal cannot suppress a v1 page invite either',
    () async {
      final h = _Harness();
      final page = await h.drainPage([
        (signal: _v1Invite(), handle: _callHandle),
        (signal: _v2(event: 'terminate', sequence: 2), handle: _callHandle),
      ]);
      expect(page.frames.first.terminalFollows, isFalse);
      expect(page.outcomes, [
        IncomingCallSignalOutcome.accepted,
        IncomingCallSignalOutcome.rejected,
      ]);
      expect(h.contexts.read(_callId)!.wireVersion, CallWireVersion.v1);
      expect(h.coordinator.activeSession!.state, CallState.ringing);
      expect(h.native.cancelled, 0);
      expect(page.settled, isEmpty);
    },
  );

  test(
    'default-off rejects v2 before context, presentation or effects',
    () async {
      final h = _Harness(videoEnabled: false);
      expect(await h.receive(_v2()), IncomingCallSignalOutcome.rejected);
      expect(h.contexts.length, 0);
      expect(h.presenter.calls, 0);
      expect(h.effects.effects, isEmpty);
    },
  );

  test(
    'v1 audio invitation retains the ordinary canonical lifecycle',
    () async {
      final h = _Harness();
      expect(await h.receive(_v1Invite()), IncomingCallSignalOutcome.accepted);
      expect(h.contexts.read(_callId)!.wireVersion, CallWireVersion.v1);
      expect(h.coordinator.activeSession!.state, CallState.ringing);
      expect(h.presenter.calls, 1);
    },
  );

  test('v2 invite captures typed context and rings exactly once', () async {
    final h = _Harness();
    final frame = await h.frame(_v2());
    expect(await h.handler.handle(frame), IncomingCallSignalOutcome.accepted);
    expect(h.contexts.read(_callId)!.wireVersion, CallWireVersion.v2);
    expect(h.contexts.read(_callId)!.requestedMedia, CallMediaKind.video);
    expect(h.contexts.read(_callId)!.initialAcceptedMedia, isNull);
    expect(h.coordinator.activeSession!.state, CallState.ringing);
    expect(await h.handler.handle(frame), IncomingCallSignalOutcome.duplicate);
    expect(h.presenter.calls, 1);
  });

  test('v2 peeking is typed and rolls back its replay reservation', () async {
    final h = _Harness();
    final invite = await h.frame(_v2(), mailbox: true);
    final terminal = await h.frame(
      _v2(event: 'terminate', sequence: 2),
      mailbox: true,
    );
    final peek = await h.handler.peek(invite);
    expect(peek, isNotNull);
    expect(peek!.isInvite, isTrue);
    expect(peek.videoEvent, CallSignalV2Type.invite);
    expect((await h.handler.peek(terminal))!.isTerminal, isTrue);
    expect(h.contexts.length, 0);
    expect(h.effects.effects, isEmpty);
    expect(await h.handler.handle(invite), IncomingCallSignalOutcome.accepted);
    expect(
      await h.handler.handle(terminal),
      IncomingCallSignalOutcome.accepted,
    );
  });

  test(
    'same-page terminal suppresses v2 invite without context or ringing',
    () async {
      final h = _Harness();
      final invite = await h.frame(_v2(), mailbox: true, terminalFollows: true);
      expect(
        await h.handler.handle(invite),
        IncomingCallSignalOutcome.superseded,
      );
      expect(h.presenter.calls, 0);
      expect(h.contexts.length, 0);
      expect(h.effects.effects, isEmpty);
      final terminal = await h.handler.handleMailbox(
        await h.frame(_v2(event: 'terminate', sequence: 2), mailbox: true),
      );
      expect(terminal.authenticatedTerminal!.signal, isA<CallSignalV2>());
      expect(h.coordinator.isTerminalCall(_callId), isTrue);
      expect(h.native.cancelled, 1);
    },
  );

  test(
    'v2 terminal proves exact mailbox custody and cancels native first',
    () async {
      final h = _Harness();
      await h.admitIncoming();
      var nativePrecedesTerminal = false;
      h.native.onCancel = () {
        nativePrecedesTerminal =
            h.coordinator.activeSession?.isTerminal == false;
      };
      final terminal = _v2(event: 'terminate', sequence: 2);
      final result = await h.handler.handleMailbox(
        await h.frame(terminal, mailbox: true),
      );
      expect(result.outcome, IncomingCallSignalOutcome.accepted);
      expect(result.authenticatedTerminal!.signal.toMap(), terminal.toMap());
      expect(result.authenticatedTerminal!.signal, isA<CallSignalV2>());
      expect(result.authenticatedTerminal!.callHandle, _callHandle);
      expect(nativePrecedesTerminal, isTrue);
      expect(h.contexts.read(_callId), isNull);
      expect(h.coordinator.isTerminalCall(_callId), isTrue);
    },
  );

  test('wrong mailbox identity cannot produce terminal custody', () async {
    final h = _Harness();
    final result = await h.handler.handleMailbox(
      await h.frame(
        _v2(event: 'terminate'),
        mailbox: true,
        expectedMessageId: '99999999-9999-4999-8999-999999999999',
      ),
    );
    expect(result.outcome, IncomingCallSignalOutcome.rejected);
    expect(result.authenticatedTerminal, isNull);
    expect(h.contexts.length, 0);
    expect(h.coordinator.isTerminalCall(_callId), isFalse);
  });

  test(
    'late v2 accept cannot recreate context after terminal cleanup',
    () async {
      final h = _Harness();
      await h.admitIncoming();
      await h.receive(_v2(event: 'terminate', sequence: 2));
      final late = await h.frame(_v2(event: 'accept', sequence: 3));
      final effectCount = h.effects.effects.length;
      expect(await h.handler.handle(late), IncomingCallSignalOutcome.duplicate);
      expect(await h.handler.handle(late), IncomingCallSignalOutcome.duplicate);
      expect(h.contexts.read(_callId), isNull);
      expect(h.effects.effects.length, effectCount);
      expect(h.coordinator.activeSession, isNull);
    },
  );

  test('v2 traffic cannot rebind or purge a live v1 audio context', () async {
    final h = _Harness();
    await h.receive(_v1Invite());
    expect(
      await h.receive(_v2(event: 'accept', sequence: 2)),
      IncomingCallSignalOutcome.rejected,
    );
    expect(h.contexts.read(_callId)!.wireVersion, CallWireVersion.v1);
    expect(h.coordinator.activeSession!.state, CallState.ringing);
    expect(h.presenter.calls, 1);
  });

  test(
    'unbound nonterminal v2 control is rejected without inventing a call',
    () async {
      final h = _Harness();
      expect(
        await h.receive(_v2(event: 'accept')),
        IncomingCallSignalOutcome.rejected,
      );
      expect(h.contexts.length, 0);
      expect(h.effects.effects, isEmpty);
    },
  );

  test(
    'v2 context requires a typed observer and never uses legacy capture',
    () async {
      final observer = _LegacyObserver();
      final h = _Harness(observer: observer);
      expect(await h.receive(_v2()), IncomingCallSignalOutcome.rejected);
      expect(observer.captured, 0);
      expect(h.presenter.calls, 0);
      expect(h.effects.effects, isEmpty);
    },
  );

  test(
    'context capacity failure defers and permits the same envelope retry',
    () async {
      final h = _Harness(contextCapacity: 1);
      h.contexts.captureAuthenticatedV2(
        signal: _v2(callId: _otherCall),
        callHandle: _callHandle,
      );
      final invite = await h.frame(_v2());
      expect(
        await h.handler.handle(invite),
        IncomingCallSignalOutcome.deferred,
      );
      expect(h.presenter.calls, 0);
      h.contexts.purge(_otherCall);
      expect(
        await h.handler.handle(invite),
        IncomingCallSignalOutcome.accepted,
      );
      expect(h.presenter.calls, 1);
    },
  );

  test('v2 ringing and accept use the canonical outgoing call', () async {
    final h = _Harness();
    await h.outgoing();
    expect(
      await h.receive(_v2(event: 'ringing')),
      IncomingCallSignalOutcome.accepted,
    );
    expect(
      await h.receive(_v2(event: 'accept', sequence: 2, media: 'audio')),
      IncomingCallSignalOutcome.accepted,
    );
    expect(h.contexts.read(_callId)!.initialAcceptedMedia, CallMediaKind.audio);
    expect(h.coordinator.activeSession!.state, CallState.accepted);
    expect(h.presenter.calls, 0);
  });

  for (final event in <String>[
    'offer',
    'answer',
    'ice',
    'ice_restart',
    'media_request',
    'media_response',
    'media_commit',
    'media_commit_ack',
    'media_abort',
    'camera_state',
  ]) {
    test('v2 $event goes only to the typed bounded media owner', () async {
      CallSignalV2? received;
      var receivedHandle = '';
      var current = false;
      final h = _Harness(
        onMedia: ({required signal, required callHandle, required canApply}) {
          received = signal;
          receivedHandle = callHandle;
          current = canApply();
          return IncomingCallSignalOutcome.accepted;
        },
      );
      await h.admitIncoming();
      h.contexts.recordLocalAcceptance(_callId, media: CallMediaKind.video);
      final before = List<CallEffectType>.of(h.effects.effects);
      final signal = _v2(event: event, sequence: 2);
      expect(await h.receive(signal), IncomingCallSignalOutcome.accepted);
      expect(received!.toMap(), signal.toMap());
      expect(receivedHandle, _callHandle);
      expect(current, isTrue);
      expect(h.effects.effects, before);
      expect(h.coordinator.activeSession!.isTerminal, isFalse);
    });
  }

  test(
    'unwired v2 media is refused without the legacy media effects',
    () async {
      final h = _Harness();
      await h.admitIncoming();
      final before = List<CallEffectType>.of(h.effects.effects);
      expect(
        await h.receive(_v2(event: 'media_request', sequence: 2)),
        IncomingCallSignalOutcome.rejected,
      );
      expect(h.effects.effects, before);
      expect(h.contexts.read(_callId), isNotNull);
      expect(h.coordinator.activeSession!.isTerminal, isFalse);
    },
  );

  test(
    'deferred media releases replay for retry, then duplicate is suppressed',
    () async {
      var calls = 0;
      final h = _Harness(
        onMedia: ({required signal, required callHandle, required canApply}) {
          calls++;
          return calls == 1
              ? IncomingCallSignalOutcome.deferred
              : IncomingCallSignalOutcome.accepted;
        },
      );
      await h.admitIncoming();
      final frame = await h.frame(_v2(event: 'media_request', sequence: 2));
      expect(await h.handler.handle(frame), IncomingCallSignalOutcome.deferred);
      expect(await h.handler.handle(frame), IncomingCallSignalOutcome.accepted);
      expect(
        await h.handler.handle(frame),
        IncomingCallSignalOutcome.duplicate,
      );
      expect(calls, 2);
    },
  );

  test(
    'media owner exception defers retry without ending the audio call',
    () async {
      var calls = 0;
      final h = _Harness(
        onMedia: ({required signal, required callHandle, required canApply}) {
          if (++calls == 1) throw StateError('temporary queue failure');
          return IncomingCallSignalOutcome.accepted;
        },
      );
      await h.admitIncoming();
      final frame = await h.frame(_v2(event: 'media_request', sequence: 2));
      final before = List<CallEffectType>.of(h.effects.effects);
      expect(await h.handler.handle(frame), IncomingCallSignalOutcome.deferred);
      expect(h.coordinator.activeSession!.isTerminal, isFalse);
      expect(await h.handler.handle(frame), IncomingCallSignalOutcome.accepted);
      expect(h.effects.effects, before);
    },
  );

  test('adopted media current fence closes after terminal', () async {
    bool Function()? fence;
    final h = _Harness(
      onMedia: ({required signal, required callHandle, required canApply}) {
        fence = canApply;
        return IncomingCallSignalOutcome.accepted;
      },
    );
    await h.admitIncoming();
    await h.receive(_v2(event: 'media_request', sequence: 2));
    expect(fence!(), isTrue);
    await h.receive(_v2(event: 'terminate', sequence: 3));
    expect(fence!(), isFalse);
    expect(h.contexts.read(_callId), isNull);
  });

  test(
    'adopted media stops while authenticated native cancellation waits',
    () async {
      bool Function()? fence;
      final h = _Harness(
        onMedia: ({required signal, required callHandle, required canApply}) {
          fence = canApply;
          return IncomingCallSignalOutcome.accepted;
        },
      );
      await h.admitIncoming();
      await h.receive(_v2(event: 'media_request', sequence: 2));
      expect(fence!(), isTrue);
      h.native.cancelGate = Completer<void>();
      final terminal = h.receive(_v2(event: 'terminate', sequence: 3));
      addTearDown(() async {
        if (!h.native.cancelGate!.isCompleted) h.native.cancelGate!.complete();
        await terminal;
      });
      await Future.any<void>([
        h.native.cancelStarted.future,
        terminal.then<void>((_) {}),
      ]);
      expect(h.native.cancelled, 1);
      expect(h.coordinator.activeSession!.isTerminal, isFalse);
      expect(fence!(), isFalse);
      expect(
        await h.receive(_v2(event: 'accept', sequence: 4)),
        IncomingCallSignalOutcome.duplicate,
      );
      h.native.cancelGate!.complete();
      expect(await terminal, IncomingCallSignalOutcome.accepted);
      expect(fence!(), isFalse);
    },
  );

  test(
    'adopted media current fence closes when the envelope expires',
    () async {
      bool Function()? fence;
      final h = _Harness(
        onMedia: ({required signal, required callHandle, required canApply}) {
          fence = canApply;
          return IncomingCallSignalOutcome.accepted;
        },
      );
      await h.admitIncoming();
      await h.receive(_v2(event: 'media_request', sequence: 2));
      expect(fence!(), isTrue);
      h.nowMs += 45000;
      expect(fence!(), isFalse);
    },
  );

  test(
    'late media is tombstoned before context capture or owner dispatch',
    () async {
      var calls = 0;
      final h = _Harness(
        onMedia: ({required signal, required callHandle, required canApply}) {
          calls++;
          return IncomingCallSignalOutcome.accepted;
        },
      );
      await h.admitIncoming();
      await h.receive(_v2(event: 'terminate', sequence: 2));
      expect(
        await h.receive(_v2(event: 'media_request', sequence: 3)),
        IncomingCallSignalOutcome.duplicate,
      );
      expect(calls, 0);
      expect(h.contexts.read(_callId), isNull);
    },
  );

  test('unknown v2 media cannot reach the current call owner', () async {
    var calls = 0;
    final h = _Harness(
      onMedia: ({required signal, required callHandle, required canApply}) {
        calls++;
        return IncomingCallSignalOutcome.accepted;
      },
    );
    await h.admitIncoming();
    expect(
      await h.receive(
        _v2(event: 'media_request', callId: _otherCall, sequence: 2),
      ),
      IncomingCallSignalOutcome.rejected,
    );
    expect(calls, 0);
    expect(h.contexts.read(_otherCall), isNull);
    expect(h.coordinator.activeSession!.callId, _callId);
  });

  test(
    'network hold defers v2 before authentication and preserves retry',
    () async {
      final h = _Harness();
      final frame = await h.frame(_v2());
      h.networkAllowed = false;
      expect(await h.handler.handle(frame), IncomingCallSignalOutcome.deferred);
      expect(h.contexts.length, 0);
      h.networkAllowed = true;
      expect(await h.handler.handle(frame), IncomingCallSignalOutcome.accepted);
    },
  );

  test(
    'terminal during presentation dismisses late UI and never revives v2',
    () async {
      final h = _Harness();
      h.presenter.gate = Completer<bool>();
      final incoming = h.receive(_v2());
      addTearDown(() async {
        if (!h.presenter.gate!.isCompleted) h.presenter.gate!.complete(false);
        await incoming;
      });
      // A RED implementation may reject before presenting; bound this wait to
      // the handler result so the expected failure does not hang the test lane.
      await Future.any<void>([
        h.presenter.started.future,
        incoming.then<void>((_) {}),
      ]);
      expect(h.presenter.calls, 1);
      expect(
        await h.receive(_v2(event: 'terminate', sequence: 2)),
        IncomingCallSignalOutcome.accepted,
      );
      h.presenter.gate!.complete(true);
      expect(await incoming, IncomingCallSignalOutcome.rejected);
      expect(h.presenter.dismissals, 1);
      expect(h.coordinator.isTerminalCall(_callId), isTrue);
      expect(h.contexts.read(_callId), isNull);
    },
  );
}
