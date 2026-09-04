import 'dart:convert';

import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_test/flutter_test.dart';

const _nowMs = 5_000_000;
const _routingHandle = '0123456789abcdef0123456789abcdef';
const _wakeHandle = 'fedcba9876543210fedcba9876543210';

TrustedCallDeviceAuthority _trusted({
  String account = 'contact-account',
  String device = 'contactdevice',
  bool linked = true,
  int deviceKeyEpoch = 7,
}) => TrustedCallDeviceAuthority(
  accountPeerId: account,
  devicePeerId: device,
  linked: linked,
  deviceKeyEpoch: deviceKeyEpoch,
  signingPublicKey: 'signing-public-key',
  mlKemPublicKey: 'mlkem-public-key',
);

SignedCallEndpointRecord _relay({
  String account = 'contact-account',
  String device = 'contactdevice',
  String signature = 'valid-signature',
  int deviceKeyEpoch = 7,
  int preferenceEpoch = 11,
  int expiresAtMs = _nowMs + 60_000,
  bool tamperCanonical = false,
}) {
  final record = CallEndpointRecord(
    accountPeerId: account,
    devicePeerId: device,
    capabilities: const <String>{'voice_call_v1'},
    platform: CallEndpointPlatform.android,
    expiresAtMs: expiresAtMs,
    preferenceEpoch: preferenceEpoch,
    deviceKeyEpoch: deviceKeyEpoch,
    routingHandle: _routingHandle,
  );
  return SignedCallEndpointRecord(
    record: record,
    signature: signature,
    canonicalRecordBase64: base64Encode(
      utf8.encode(
        tamperCanonical
            ? '${record.canonicalRecordJson} '
            : record.canonicalRecordJson,
      ),
    ),
  );
}

CallWakeHandleGrant _grant({
  String recipientDevicePeerId = 'contactdevice',
  int deviceKeyEpoch = 7,
  int generation = 3,
  int issuedAtMs = _nowMs - 1_000,
  int expiresAtMs = _nowMs + 30_000,
}) => CallWakeHandleGrant(
  handle: _wakeHandle,
  recipientDevicePeerId: recipientDevicePeerId,
  deviceKeyEpoch: deviceKeyEpoch,
  generation: generation,
  issuedAtMs: issuedAtMs,
  expiresAtMs: expiresAtMs,
);

Future<bool> _verify(
  SignedCallEndpointRecord endpoint,
  String trustedSigningPublicKey,
) async =>
    endpoint.signature == 'valid-signature' &&
    trustedSigningPublicKey == 'signing-public-key' &&
    endpoint.canonicalRecordJson == endpoint.record.canonicalRecordJson;

void main() {
  late CallEndpointResolver resolver;

  setUp(() {
    resolver = CallEndpointResolver(
      nowMs: () => _nowMs,
      verifyEndpointSignature: _verify,
    );
  });

  test(
    'resolves only the trusted-roster and signed capability intersection',
    () async {
      final endpoint = await resolver.resolve(
        contactAccountPeerId: 'contact-account',
        contactAccepted: true,
        contactBlocked: false,
        trustedDevices: <TrustedCallDeviceAuthority>[_trusted()],
        relayCapabilities: <SignedCallEndpointRecord>[_relay()],
        wakeHandleGrant: _grant(),
      );

      expect(endpoint.devicePeerId, 'contactdevice');
      expect(endpoint.deviceKeyEpoch, 7);
      expect(endpoint.preferenceEpoch, 11);
      expect(endpoint.mlKemPublicKey, 'mlkem-public-key');
      expect(endpoint.wakeHandle, _wakeHandle);
      expect(endpoint.wakeHandle, isNot(endpoint.routingHandle));
    },
  );

  test(
    'fails closed without a current grant for the resolved device key epoch',
    () async {
      final cases = <CallWakeHandleGrant?>[
        null,
        _grant(recipientDevicePeerId: 'otherdevice'),
        _grant(deviceKeyEpoch: 8),
        _grant(expiresAtMs: _nowMs),
      ];

      for (final grant in cases) {
        await expectLater(
          resolver.resolve(
            contactAccountPeerId: 'contact-account',
            contactAccepted: true,
            contactBlocked: false,
            trustedDevices: <TrustedCallDeviceAuthority>[_trusted()],
            relayCapabilities: <SignedCallEndpointRecord>[_relay()],
            wakeHandleGrant: grant,
          ),
          throwsA(isA<CallEndpointResolutionException>()),
          reason: 'grant: ${grant?.toCanonicalMap()}',
        );
      }
    },
  );

  test(
    'fails closed on empty, relay-only, and roster-only authority',
    () async {
      final cases =
          <
            ({
              List<TrustedCallDeviceAuthority> trusted,
              List<SignedCallEndpointRecord> relay,
            })
          >[
            (trusted: const [], relay: const []),
            (trusted: const [], relay: <SignedCallEndpointRecord>[_relay()]),
            (
              trusted: <TrustedCallDeviceAuthority>[_trusted()],
              relay: const [],
            ),
          ];

      for (final entry in cases) {
        await expectLater(
          resolver.resolve(
            contactAccountPeerId: 'contact-account',
            contactAccepted: true,
            contactBlocked: false,
            trustedDevices: entry.trusted,
            relayCapabilities: entry.relay,
          ),
          throwsA(isA<CallEndpointResolutionException>()),
        );
      }
    },
  );

  test(
    'fails closed on stale, wrong, unlinked, forged, and blocked records',
    () async {
      final cases =
          <
            ({
              bool blocked,
              TrustedCallDeviceAuthority trusted,
              SignedCallEndpointRecord relay,
              CallEndpointResolutionCode code,
            })
          >[
            (
              blocked: false,
              trusted: _trusted(),
              relay: _relay(expiresAtMs: _nowMs),
              code: CallEndpointResolutionCode.stale,
            ),
            (
              blocked: false,
              trusted: _trusted(),
              relay: _relay(account: 'wrong-account'),
              code: CallEndpointResolutionCode.mismatched,
            ),
            (
              blocked: false,
              trusted: _trusted(linked: false),
              relay: _relay(),
              code: CallEndpointResolutionCode.unlinked,
            ),
            (
              blocked: false,
              trusted: _trusted(),
              relay: _relay(signature: 'forged'),
              code: CallEndpointResolutionCode.invalidSignature,
            ),
            (
              blocked: false,
              trusted: _trusted(),
              relay: _relay(tamperCanonical: true),
              code: CallEndpointResolutionCode.invalidSignature,
            ),
            (
              blocked: true,
              trusted: _trusted(),
              relay: _relay(),
              code: CallEndpointResolutionCode.blocked,
            ),
          ];

      for (final entry in cases) {
        await expectLater(
          resolver.resolve(
            contactAccountPeerId: 'contact-account',
            contactAccepted: true,
            contactBlocked: entry.blocked,
            trustedDevices: <TrustedCallDeviceAuthority>[entry.trusted],
            relayCapabilities: <SignedCallEndpointRecord>[entry.relay],
          ),
          throwsA(
            isA<CallEndpointResolutionException>().having(
              (error) => error.code,
              'code',
              entry.code,
            ),
          ),
        );
      }
    },
  );

  test(
    'fails closed instead of choosing among ambiguous current endpoints',
    () async {
      await expectLater(
        resolver.resolve(
          contactAccountPeerId: 'contact-account',
          contactAccepted: true,
          contactBlocked: false,
          trustedDevices: <TrustedCallDeviceAuthority>[
            _trusted(),
            _trusted(device: 'seconddevice'),
          ],
          relayCapabilities: <SignedCallEndpointRecord>[
            _relay(),
            _relay(device: 'seconddevice'),
          ],
        ),
        throwsA(
          isA<CallEndpointResolutionException>().having(
            (error) => error.code,
            'code',
            CallEndpointResolutionCode.ambiguous,
          ),
        ),
      );
    },
  );

  test(
    'diagnostic error text never includes endpoint identity or handle',
    () async {
      Object? captured;
      try {
        await resolver.resolve(
          contactAccountPeerId: 'contact-account',
          contactAccepted: true,
          contactBlocked: false,
          trustedDevices: <TrustedCallDeviceAuthority>[_trusted()],
          relayCapabilities: <SignedCallEndpointRecord>[
            _relay(device: 'wrongdevice'),
          ],
        );
      } catch (error) {
        captured = error;
      }

      expect(captured, isA<CallEndpointResolutionException>());
      expect(captured.toString(), isNot(contains('contact-account')));
      expect(captured.toString(), isNot(contains('wrongdevice')));
      expect(
        captured.toString(),
        isNot(contains('0123456789abcdef0123456789abcdef')),
      );
      expect(captured.toString(), isNot(contains(_wakeHandle)));
    },
  );
}
