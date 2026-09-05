import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/application/call_signaling_service.dart';
import 'package:flutter_app/features/call/application/headless_call_decline_reply.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_app/features/call/infrastructure/p2p_call_transport.dart';
import 'package:flutter_test/flutter_test.dart';

const _callId = '22222222-2222-4222-8222-222222222222';
// The mailbox handle the invite row was stored under: the caller mints it
// apart from the call id (ProductionCallControlSignalingAdapter forbids the
// two to be equal), so the reply must ride it, never the call id.
const _mailboxHandle = '33333333-3333-4333-8333-333333333333';
const _inviteMessageId = '44444444-4444-4444-8444-444444444444';
const _replyMessageId = '55555555-5555-4555-8555-555555555555';
const _now = 1_800_000_000_000;

typedef _Transmitted = ({
  CallSignal signal,
  String callHandle,
  ResolvedCallEndpoint endpoint,
  String signingKey,
});

CallSignal _invite({
  CallSignalType event = CallSignalType.invite,
  String recipientAccountPeerId = 'local-account',
  String recipientDevicePeerId = 'local-device',
}) => CallSignal.create(
  callId: CallId.parse(_callId),
  messageId: _inviteMessageId,
  event: event,
  senderAccountPeerId: 'caller-account',
  senderDevicePeerId: 'caller-device',
  recipientAccountPeerId: recipientAccountPeerId,
  recipientDevicePeerId: recipientDevicePeerId,
  senderSequence: 1,
  iceGeneration: 3,
  createdAtMs: _now - 5_000,
  expiresAtMs: _now + 35_000,
  payload: event == CallSignalType.invite
      ? const <String, Object?>{
          'capabilities': <Object?>['audio'],
          'metadata': <String, Object?>{'media': 'audio', 'video': false},
        }
      : const <String, Object?>{'reason': 'local_hangup'},
);

ResolvedCallEndpoint _endpoint({String devicePeerId = 'caller-device'}) =>
    ResolvedCallEndpoint(
      accountPeerId: 'caller-account',
      devicePeerId: devicePeerId,
      signingPublicKey: 'caller-signing-key',
      mlKemPublicKey: 'caller-kem-key',
      deviceKeyEpoch: 1,
      preferenceEpoch: 1,
      platform: CallEndpointPlatform.ios,
      expiresAtMs: _now + 60_000,
      routingHandle: 'caller-routing-handle',
      wakeHandle: 'a' * 32,
    );

void main() {
  late List<_Transmitted> transmitted;
  late List<String> resolved;
  late CallSignalTransportResult Function() result;
  late ResolvedCallEndpoint Function() endpoint;
  late HeadlessCallDeclineReplyTransmitter transmitter;

  setUp(() {
    transmitted = <_Transmitted>[];
    resolved = <String>[];
    result = () => const CallSignalTransportResult(
      directAccepted: true,
      mailboxStored: false,
      directRoute: CallDirectRoute.circuitRelay,
    );
    endpoint = () => _endpoint();
    transmitter = HeadlessCallDeclineReplyTransmitter(
      transmit:
          ({
            required signal,
            required callHandle,
            required endpoint,
            required senderSigningPrivateKey,
          }) async {
            transmitted.add((
              signal: signal,
              callHandle: callHandle,
              endpoint: endpoint,
              signingKey: senderSigningPrivateKey,
            ));
            return result();
          },
      resolveEndpoint: (contactAccountPeerId) async {
        resolved.add(contactAccountPeerId);
        return endpoint();
      },
      localAccountPeerId: 'local-account',
      localDevicePeerId: 'local-device',
      loadSigningPrivateKey: () async => 'local-signing-key',
      nowMs: () => _now,
      messageIdSource: () => _replyMessageId,
    );
  });

  test(
    'replies to the inviting device with one signed declined reject',
    () async {
      expect(
        await transmitter.sendDeclineFor(_invite(), callHandle: _mailboxHandle),
        isTrue,
      );

      expect(resolved, <String>['caller-account']);
      final sent = transmitted.single;
      expect(sent.callHandle, _mailboxHandle);
      expect(sent.signingKey, 'local-signing-key');
      expect(sent.endpoint.devicePeerId, 'caller-device');
      final signal = sent.signal;
      expect(signal.event, CallSignalType.reject);
      expect(signal.callId.value, _callId);
      expect(signal.messageId, _replyMessageId);
      expect(signal.senderAccountPeerId, 'local-account');
      expect(signal.senderDevicePeerId, 'local-device');
      expect(signal.recipientAccountPeerId, 'caller-account');
      expect(signal.recipientDevicePeerId, 'caller-device');
      expect(signal.senderSequence, 1);
      expect(signal.iceGeneration, 3);
      expect(signal.createdAtMs, _now);
      expect(signal.expiresAtMs, _now + 40_000);
      expect(signal.payload, const <String, Object?>{'reason': 'declined'});
    },
  );

  test('a mailbox-only custody also counts as delivered', () async {
    result = () => const CallSignalTransportResult(
      directAccepted: false,
      mailboxStored: true,
      directRoute: CallDirectRoute.unknown,
      wakeDispatched: true,
    );
    expect(
      await transmitter.sendDeclineFor(_invite(), callHandle: _mailboxHandle),
      isTrue,
    );
    expect(transmitted, hasLength(1));
  });

  test('replies only to an invite addressed to this exact device', () async {
    for (final signal in <CallSignal>[
      _invite(event: CallSignalType.terminate),
      _invite(recipientAccountPeerId: 'other-account'),
      _invite(recipientDevicePeerId: 'other-device'),
    ]) {
      expect(
        await transmitter.sendDeclineFor(signal, callHandle: _mailboxHandle),
        isFalse,
      );
    }
    expect(transmitted, isEmpty);
    expect(resolved, isEmpty);
  });

  test(
    'a caller endpoint that is no longer the inviting device is refused',
    () async {
      endpoint = () => _endpoint(devicePeerId: 'caller-second-device');
      expect(
        await transmitter.sendDeclineFor(_invite(), callHandle: _mailboxHandle),
        isFalse,
      );
      expect(transmitted, isEmpty);
    },
  );

  // Device 2026-09-05 18:23Z (captures fresh-260905201908): the first reply
  // rode the call id as its mailbox handle. The iPhone received it on both
  // legs (direct message decrypted, VoIP wake drained) and dropped it
  // silently: the caller's context is keyed by the handle it minted.
  test(
    'a reply under the call id itself or a malformed handle is refused',
    () async {
      for (final handle in <String>[_callId, 'readable-handle', '', 'A' * 32]) {
        expect(
          await transmitter.sendDeclineFor(_invite(), callHandle: handle),
          isFalse,
          reason: handle,
        );
      }
      expect(transmitted, isEmpty);
      expect(resolved, isEmpty);
    },
  );

  test(
    'resolution or transport failures never throw and report false',
    () async {
      endpoint = () => throw const CallEndpointResolutionException(
        CallEndpointResolutionCode.unavailable,
      );
      expect(
        await transmitter.sendDeclineFor(_invite(), callHandle: _mailboxHandle),
        isFalse,
      );

      endpoint = () => _endpoint();
      result = () => throw const CallSignalingException(
        CallSignalingErrorCode.transportUnavailable,
      );
      expect(
        await transmitter.sendDeclineFor(_invite(), callHandle: _mailboxHandle),
        isFalse,
      );

      result = () => const CallSignalTransportResult(
        directAccepted: false,
        mailboxStored: false,
        directRoute: CallDirectRoute.unknown,
      );
      expect(
        await transmitter.sendDeclineFor(_invite(), callHandle: _mailboxHandle),
        isFalse,
      );
    },
  );
}
