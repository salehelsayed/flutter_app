import 'dart:convert';

import 'package:flutter_app/features/call/application/call_video_capability_admission.dart';
import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_test/flutter_test.dart';

// Frozen v1 byte fixtures. Build labels describe compatibility roles, not
// execution of those historical signed artifacts.
const _prefix =
    '{"schema":"mknoon.call_signal.v1",'
    '"call_id":"22222222-2222-4222-8222-222222222222",'
    '"message_id":"33333333-3333-4333-8333-333333333333","event":"';
const _suffix =
    '","sender_account_peer_id":"sender-account",'
    '"sender_device_peer_id":"sender-device",'
    '"recipient_account_peer_id":"recipient-account",'
    '"recipient_device_peer_id":"recipient-device",'
    '"sender_sequence":1,"ice_generation":0,'
    '"created_at_ms":1788091200000,"expires_at_ms":1788091245000,"payload":';
const _payloads = <String, String>{
  'invite': '{"capabilities":["voice_call_v1"],"metadata":{"audio":true}}',
  'ringing': '{}',
  'accept': '{}',
  'reject': '{"reason":"declined"}',
  'offer': '{"description":"opaque-sdp","fingerprint":"sha-256 AA:BB:CC"}',
  'answer': '{"description":"opaque-sdp","fingerprint":"sha-256 AA:BB:CC"}',
  'ice': '{"candidate":"opaque-candidate","media_id":"0","media_line_index":0}',
  'ice_restart': '{}',
  'terminate': '{"reason":"local_hangup"}',
};

void main() {
  for (final entry in _payloads.entries) {
    test('v1 ${entry.key} retains exact canonical JSON bytes', () {
      final raw = '$_prefix${entry.key}$_suffix${entry.value}}';
      final signal = CallSignal.fromMap(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      );
      expect(
        utf8.encode(jsonEncode(signal.toMap())),
        orderedEquals(utf8.encode(raw)),
      );
      expect(signal.toMap().containsKey('requested_media'), isFalse);
      expect(signal.toMap().containsKey('media_revision'), isFalse);
    });
  }

  for (final sender in ['126', '131', 'new']) {
    for (final recipient in ['126', '131', 'new']) {
      test('capability compatibility fixture $sender to $recipient', () async {
        var lookups = 0;
        final future = resolveVideoCallEndpoint(
          contactAccountPeerId: 'recipient-account',
          videoEnabled: sender == 'new',
          nowMs: () => 1788091200000,
          resolveEndpoint: (_) async {
            lookups++;
            return ResolvedCallEndpoint(
              accountPeerId: 'recipient-account',
              devicePeerId: 'recipient-device',
              signingPublicKey: 'signing',
              mlKemPublicKey: 'kem',
              deviceKeyEpoch: 1,
              preferenceEpoch: 1,
              platform: CallEndpointPlatform.android,
              expiresAtMs: 1788091245000,
              routingHandle: '0123456789abcdef0123456789abcdef',
              wakeHandle: 'fedcba9876543210fedcba9876543210',
              capabilities: {
                'voice_call_v1',
                if (recipient == 'new') 'video_call_v2',
              },
            );
          },
        );
        if (sender == 'new' && recipient == 'new') {
          expect((await future).devicePeerId, 'recipient-device');
        } else {
          await expectLater(
            future,
            throwsA(
              isA<CallVideoAdmissionException>().having(
                (error) => error.reason,
                'reason',
                sender == 'new'
                    ? CallVideoAdmissionFailure.unsupported
                    : CallVideoAdmissionFailure.disabled,
              ),
            ),
          );
        }
        expect(lookups, sender == 'new' ? 1 : 0);
        final raw = '${_prefix}invite$_suffix${_payloads['invite']}}';
        final signal = CallSignal.fromMap(
          Map<String, Object?>.from(jsonDecode(raw) as Map),
        );
        expect(jsonEncode(signal.toMap()), raw);
      });
    }
  }
}
