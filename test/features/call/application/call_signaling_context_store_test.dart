import 'package:flutter_app/features/call/application/call_signaling_context_store.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_test/flutter_test.dart';

final _callA = CallId.parse('11111111-1111-4111-8111-111111111111');
final _callB = CallId.parse('22222222-2222-4222-8222-222222222222');

CallSignal _incoming({
  required CallId callId,
  int senderSequence = 1,
  int iceGeneration = 0,
  String? messageId,
  CallSignalType event = CallSignalType.invite,
  Map<String, Object?> payload = const <String, Object?>{},
}) => CallSignal.create(
  callId: callId,
  messageId:
      messageId ??
      (senderSequence == 1
          ? '33333333-3333-4333-8333-333333333333'
          : '44444444-4444-4444-8444-444444444444'),
  event: event,
  senderAccountPeerId: 'remote-account',
  senderDevicePeerId: 'remote-device',
  recipientAccountPeerId: 'local-account',
  recipientDevicePeerId: 'local-device',
  senderSequence: senderSequence,
  iceGeneration: iceGeneration,
  createdAtMs: 1_000,
  expiresAtMs: 46_000,
  payload: payload,
);

void main() {
  test('contexts and pending invite selection remain strictly bounded', () {
    final store = CallSignalingContextStore(maxContexts: 1);
    store.captureAuthenticated(
      signal: _incoming(callId: _callA),
      callHandle: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    );

    expect(store.length, 1);
    expect(store.takePendingIncomingInvite()?.callId, _callA);
    expect(store.takePendingIncomingInvite(), isNull);

    expect(
      () => store.storeOutgoing(
        callId: _callB,
        callHandle: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        localAccountPeerId: 'other-local-account',
        localDevicePeerId: 'other-local-device',
        remoteAccountPeerId: 'other-remote-account',
        remoteDevicePeerId: 'other-remote-device',
      ),
      throwsA(
        isA<CallSignalingContextException>().having(
          (error) => error.code,
          'code',
          CallSignalingContextErrorCode.capacityExceeded,
        ),
      ),
    );

    final diagnostic = '$store';
    expect(diagnostic, contains('contextCount: 1'));
    for (final secret in <String>[
      _callA.value,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'remote-account',
      'remote-device',
    ]) {
      expect(diagnostic, isNot(contains(secret)));
    }
  });

  test('sender sequences and ICE generations advance monotonically', () {
    final store = CallSignalingContextStore(maxContexts: 2);
    store.captureAuthenticated(
      signal: _incoming(callId: _callA, senderSequence: 2, iceGeneration: 0),
      callHandle: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    );
    // A replay transaction may roll back after context capture. Retrying the
    // exact authenticated metadata is idempotent, while regressions are not.
    store.captureAuthenticated(
      signal: _incoming(callId: _callA, senderSequence: 2, iceGeneration: 0),
      callHandle: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    );

    final first = store.reserveNextMetadata(_callA, iceGeneration: 0);
    final second = store.reserveNextMetadata(_callA, iceGeneration: 1);
    expect(first.senderSequence, 1);
    expect(first.iceGeneration, 0);
    expect(second.senderSequence, 2);
    expect(second.iceGeneration, 1);

    expect(
      () => store.reserveNextMetadata(_callA, iceGeneration: 0),
      throwsA(
        isA<CallSignalingContextException>().having(
          (error) => error.code,
          'code',
          CallSignalingContextErrorCode.nonMonotonicMetadata,
        ),
      ),
    );
    expect(
      () => store.captureAuthenticated(
        signal: _incoming(callId: _callA, senderSequence: 3, iceGeneration: 0),
        callHandle: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      ),
      throwsA(
        isA<CallSignalingContextException>().having(
          (error) => error.code,
          'code',
          CallSignalingContextErrorCode.nonMonotonicMetadata,
        ),
      ),
    );
    expect(
      () => store.captureAuthenticated(
        signal: _incoming(callId: _callA, senderSequence: 1, iceGeneration: 1),
        callHandle: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      ),
      throwsA(
        isA<CallSignalingContextException>().having(
          (error) => error.code,
          'code',
          CallSignalingContextErrorCode.nonMonotonicMetadata,
        ),
      ),
    );

    final context = store.read(_callA);
    expect(context?.nextSenderSequence, 3);
    expect(context?.remoteSenderSequence, 2);
    expect(context?.iceGeneration, 1);
    expect('$context', isNot(contains('remote-account')));

    store.purge(_callA);
    expect(store.length, 0);
  });

  test(
    'unseen lower negotiation sequence preserves the authenticated watermark',
    () {
      final store = CallSignalingContextStore(maxContexts: 2);
      const handle = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
      final invite = _incoming(callId: _callA, senderSequence: 1);
      final ice = _incoming(
        callId: _callA,
        senderSequence: 3,
        messageId: '55555555-5555-4555-8555-555555555555',
        event: CallSignalType.ice,
        payload: const <String, Object?>{
          'candidate': 'candidate:fixture',
          'media_id': 'audio',
          'media_line_index': 0,
        },
      );
      final offer = _incoming(
        callId: _callA,
        senderSequence: 2,
        messageId: '44444444-4444-4444-8444-444444444444',
        event: CallSignalType.offer,
        payload: const <String, Object?>{
          'description': 'opaque-offer',
          'fingerprint': 'sha-256 fixture',
        },
      );

      store.captureAuthenticated(signal: invite, callHandle: handle);
      store.captureAuthenticated(signal: ice, callHandle: handle);
      expect(store.read(_callA)?.remoteSenderSequence, 3);

      // ICE and SDP can arrive over independent authenticated transports.
      // Accept the unseen lower sequence without rolling back the high-water
      // diagnostic; replay admission remains owned by the secure codec.
      store.captureAuthenticated(signal: offer, callHandle: handle);
      expect(store.read(_callA)?.remoteSenderSequence, 3);

      // Context capture is intentionally idempotent because a downstream
      // transient failure rolls back the codec reservation before retry.
      store.captureAuthenticated(signal: offer, callHandle: handle);
      expect(store.read(_callA)?.remoteSenderSequence, 3);
    },
  );
}
