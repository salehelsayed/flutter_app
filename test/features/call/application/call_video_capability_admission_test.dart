import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/application/call_video_capability_admission.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_test/flutter_test.dart';

const _now = 5000000;
const _voice = 'voice_call_v1';
const _video = 'video_call_v2';

SignedCallEndpointRecord _record(Set<String> capabilities) {
  final record = CallEndpointRecord(
    accountPeerId: 'account',
    devicePeerId: 'device',
    capabilities: capabilities,
    platform: CallEndpointPlatform.android,
    expiresAtMs: _now + 60000,
    preferenceEpoch: 2,
    deviceKeyEpoch: 1,
    routingHandle: '0123456789abcdef0123456789abcdef',
  );
  return SignedCallEndpointRecord(
    record: record,
    signature: 'valid',
    canonicalRecordBase64: base64Encode(
      utf8.encode(record.canonicalRecordJson),
    ),
  );
}

Future<ResolvedCallEndpoint> _resolve(
  SignedCallEndpointRecord record, {
  VerifyCallEndpointSignature? verify,
}) =>
    CallEndpointResolver(
      nowMs: () => _now,
      verifyEndpointSignature:
          verify ??
          (endpoint, key) async =>
              endpoint.signature == 'valid' &&
              endpoint.canonicalRecordJson ==
                  endpoint.record.canonicalRecordJson,
    ).resolve(
      contactAccountPeerId: 'account',
      contactAccepted: true,
      contactBlocked: false,
      trustedDevices: const [
        TrustedCallDeviceAuthority(
          accountPeerId: 'account',
          devicePeerId: 'device',
          linked: true,
          deviceKeyEpoch: 1,
          signingPublicKey: 'signing',
          mlKemPublicKey: 'kem',
        ),
      ],
      relayCapabilities: [record],
      wakeHandleGrant: CallWakeHandleGrant(
        handle: 'fedcba9876543210fedcba9876543210',
        recipientDevicePeerId: 'device',
        deviceKeyEpoch: 1,
        generation: 1,
        issuedAtMs: _now - 1000,
        expiresAtMs: _now + 30000,
      ),
    );

ResolvedCallEndpoint _endpoint({
  Set<String> capabilities = const {_voice, _video},
  String account = 'account',
  int expiresAtMs = _now + 30000,
}) => ResolvedCallEndpoint(
  accountPeerId: account,
  devicePeerId: 'device',
  signingPublicKey: 'signing',
  mlKemPublicKey: 'kem',
  deviceKeyEpoch: 1,
  preferenceEpoch: 2,
  platform: CallEndpointPlatform.android,
  expiresAtMs: expiresAtMs,
  routingHandle: '0123456789abcdef0123456789abcdef',
  wakeHandle: 'fedcba9876543210fedcba9876543210',
  capabilities: capabilities,
);

Matcher _failure(CallVideoAdmissionFailure reason) => throwsA(
  isA<CallVideoAdmissionException>().having(
    (error) => error.reason,
    'reason',
    reason,
  ),
);

void main() {
  test('verified endpoint retains an immutable capability snapshot', () async {
    final input = <String>{_voice, _video};
    final endpoint = await _resolve(_record(input));
    expect(endpoint.capabilities, unorderedEquals([_voice, _video]));
    input.clear();
    expect(endpoint.capabilities, unorderedEquals([_voice, _video]));
    expect(() => endpoint.capabilities.add('unsigned'), throwsUnsupportedError);
    expect(endpoint.expiresAtMs, _now + 30000);
  });

  for (final addVideo in [true, false]) {
    test(
      'signature await cannot change verified capabilities (add=$addVideo)',
      () async {
        final input = <String>{_voice, if (!addVideo) _video};
        final entered = Completer<void>();
        final release = Completer<void>();
        final pending = _resolve(
          _record(input),
          verify: (signed, key) async {
            final valid =
                signed.canonicalRecordJson == signed.record.canonicalRecordJson;
            entered.complete();
            await release.future;
            return valid;
          },
        );
        await entered.future;
        if (addVideo) {
          input.add(_video);
        } else {
          input.remove(_video);
        }
        release.complete();
        final endpoint = await pending;
        expect(
          endpoint.capabilities,
          unorderedEquals([_voice, if (!addVideo) _video]),
        );
      },
    );
  }

  test('forged endpoint never contributes video capability', () async {
    await expectLater(
      _resolve(_record({_voice, _video}), verify: (_, _) async => false),
      throwsA(
        isA<CallEndpointResolutionException>().having(
          (error) => error.code,
          'code',
          CallEndpointResolutionCode.invalidSignature,
        ),
      ),
    );
  });

  test('default-off video admission performs no endpoint lookup', () async {
    var lookups = 0;
    await expectLater(
      resolveVideoCallEndpoint(
        contactAccountPeerId: 'account',
        resolveEndpoint: (_) async {
          lookups++;
          return _endpoint();
        },
        nowMs: () => _now,
      ),
      _failure(CallVideoAdmissionFailure.disabled),
    );
    expect(lookups, 0);
  });

  test(
    'each enabled video attempt resolves fresh verified authority',
    () async {
      var lookups = 0;
      Future<ResolvedCallEndpoint> resolve(String account) {
        expect(account, 'account');
        lookups++;
        return _resolve(_record(lookups == 1 ? {_voice, _video} : {_voice}));
      }

      final endpoint = await resolveVideoCallEndpoint(
        contactAccountPeerId: 'account',
        resolveEndpoint: resolve,
        nowMs: () => _now,
        videoEnabled: true,
      );
      expect(endpoint.devicePeerId, 'device');
      await expectLater(
        resolveVideoCallEndpoint(
          contactAccountPeerId: 'account',
          resolveEndpoint: resolve,
          nowMs: () => _now,
          videoEnabled: true,
        ),
        _failure(CallVideoAdmissionFailure.unsupported),
      );
      expect(lookups, 2);
    },
  );

  for (final caps in <Set<String>>[
    {},
    {_voice},
    {_video},
    {_voice, 'video_call_v3'},
  ]) {
    test('video rejects incomplete or unknown capability set $caps', () async {
      await expectLater(
        resolveVideoCallEndpoint(
          contactAccountPeerId: 'account',
          resolveEndpoint: (_) async => _endpoint(capabilities: caps),
          nowMs: () => _now,
          videoEnabled: true,
        ),
        _failure(CallVideoAdmissionFailure.unsupported),
      );
    });
  }

  test(
    'video rejects a freshly returned endpoint for another account',
    () async {
      await expectLater(
        resolveVideoCallEndpoint(
          contactAccountPeerId: 'account',
          resolveEndpoint: (_) async => _endpoint(account: 'other'),
          nowMs: () => _now,
          videoEnabled: true,
        ),
        _failure(CallVideoAdmissionFailure.mismatched),
      );
    },
  );

  test(
    'video rechecks expiration after awaited resolution, including equality',
    () async {
      var now = _now;
      await expectLater(
        resolveVideoCallEndpoint(
          contactAccountPeerId: 'account',
          resolveEndpoint: (_) async {
            now += 30000;
            return _endpoint();
          },
          nowMs: () => now,
          videoEnabled: true,
        ),
        _failure(CallVideoAdmissionFailure.expired),
      );
    },
  );

  test(
    'video preserves lookup failure without fallback or second lookup',
    () async {
      final failure = StateError('lookup failure');
      var lookups = 0;
      await expectLater(
        resolveVideoCallEndpoint(
          contactAccountPeerId: 'account',
          resolveEndpoint: (_) async {
            lookups++;
            throw failure;
          },
          nowMs: () => _now,
          videoEnabled: true,
        ),
        throwsA(same(failure)),
      );
      expect(lookups, 1);
    },
  );
}
