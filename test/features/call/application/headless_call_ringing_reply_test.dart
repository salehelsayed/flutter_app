import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/application/call_signaling_service.dart';
import 'package:flutter_app/features/call/application/headless_call_ringing_reply.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_app/features/call/infrastructure/p2p_call_transport.dart';
import 'package:flutter_test/flutter_test.dart';

const _callId = '22222222-2222-4222-8222-222222222222';
const _handle = '33333333-3333-4333-8333-333333333333';
const _now = 1_800_000_000_000;

CallSignal _invite() => CallSignal.create(
  callId: CallId.parse(_callId),
  messageId: '44444444-4444-4444-8444-444444444444',
  event: CallSignalType.invite,
  senderAccountPeerId: 'caller-account',
  senderDevicePeerId: 'caller-device',
  recipientAccountPeerId: 'local-account',
  recipientDevicePeerId: 'local-device',
  senderSequence: 1,
  iceGeneration: 3,
  createdAtMs: _now - 5000,
  expiresAtMs: _now + 35000,
  payload: const <String, Object?>{
    'capabilities': <Object?>['audio'],
    'metadata': <String, Object?>{'media': 'audio', 'video': false},
  },
);

ResolvedCallEndpoint _endpoint({String device = 'caller-device'}) =>
    ResolvedCallEndpoint(
      accountPeerId: 'caller-account',
      devicePeerId: device,
      signingPublicKey: 'caller-signing-key',
      mlKemPublicKey: 'caller-kem-key',
      deviceKeyEpoch: 1,
      preferenceEpoch: 1,
      platform: CallEndpointPlatform.ios,
      expiresAtMs: _now + 60000,
      routingHandle: 'caller-routing-handle',
      wakeHandle: 'a' * 32,
    );

void main() {
  late List<CallSignal> sent;
  late List<String> nativeChecks;
  late bool nativeRinging;
  late String endpointDevice;
  late HeadlessCallRingingReplyTransmitter transmitter;

  setUp(() {
    sent = [];
    nativeChecks = [];
    nativeRinging = true;
    endpointDevice = 'caller-device';
    transmitter = HeadlessCallRingingReplyTransmitter(
      transmit:
          ({
            required signal,
            required callHandle,
            required endpoint,
            required senderSigningPrivateKey,
          }) async {
            expect(callHandle, _handle);
            expect(endpoint.devicePeerId, 'caller-device');
            expect(senderSigningPrivateKey, 'local-key');
            sent.add(signal);
            return const CallSignalTransportResult(
              directAccepted: true,
              mailboxStored: false,
              directRoute: CallDirectRoute.circuitRelay,
            );
          },
      resolveEndpoint: (_) async => _endpoint(device: endpointDevice),
      isNativeRinging: (handle, expiry) async {
        nativeChecks.add('$handle:$expiry');
        return nativeRinging;
      },
      localAccountPeerId: 'local-account',
      localDevicePeerId: 'local-device',
      loadSigningPrivateKey: () async => 'local-key',
      nowMs: () => _now,
      messageIdSource: () => '55555555-5555-4555-8555-555555555555',
    );
  });

  test(
    'sends authenticated ringing only while native descriptor still rings',
    () async {
      expect(
        await transmitter.sendRingingFor(_invite(), callHandle: _handle),
        isTrue,
      );
      expect(nativeChecks, <String>[
        '$_handle:${_now + 35000}',
        '$_handle:${_now + 35000}',
      ]);
      final reply = sent.single;
      expect(reply.event, CallSignalType.ringing);
      expect(reply.callId.value, _callId);
      expect(reply.senderSequence, 1);
      expect(reply.iceGeneration, 3);
      expect(reply.recipientDevicePeerId, 'caller-device');
      expect(reply.payload, isEmpty);
    },
  );

  test('ended native call and changed inviting endpoint cannot send', () async {
    nativeRinging = false;
    expect(
      await transmitter.sendRingingFor(_invite(), callHandle: _handle),
      isFalse,
    );
    expect(sent, isEmpty);

    nativeRinging = true;
    endpointDevice = 'other-device';
    expect(
      await transmitter.sendRingingFor(_invite(), callHandle: _handle),
      isFalse,
    );
    expect(sent, isEmpty);
  });

  test('a malformed or call-id handle cannot send', () async {
    for (final handle in <String>[_callId, 'wrong-handle']) {
      expect(
        await transmitter.sendRingingFor(_invite(), callHandle: handle),
        isFalse,
      );
    }
    expect(nativeChecks, isEmpty);
  });
}
