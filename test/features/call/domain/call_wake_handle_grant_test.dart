import 'dart:convert';

import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const handle = '0123456789abcdef0123456789abcdef';

  CallWakeHandleGrant grant({
    int deviceKeyEpoch = 7,
    int generation = 3,
    int issuedAtMs = 1_750_000_000_000,
    int expiresAtMs = 1_750_086_400_000,
  }) => CallWakeHandleGrant(
    handle: handle,
    recipientDevicePeerId: '12D3KooWRecipientDevice1',
    deviceKeyEpoch: deviceKeyEpoch,
    generation: generation,
    issuedAtMs: issuedAtMs,
    expiresAtMs: expiresAtMs,
  );

  test('uses the exact deterministic canonical map and roundtrips', () {
    final value = grant();

    expect(value.version, CallWakeHandleGrant.currentVersion);
    expect(value.toCanonicalMap(), <String, Object>{
      'version': 1,
      'handle': handle,
      'recipientDevicePeerId': '12D3KooWRecipientDevice1',
      'deviceKeyEpoch': 7,
      'generation': 3,
      'issuedAtMs': 1_750_000_000_000,
      'expiresAtMs': 1_750_086_400_000,
    });
    expect(
      jsonEncode(value.toCanonicalMap()),
      '{"deviceKeyEpoch":7,"expiresAtMs":1750086400000,'
      '"generation":3,"handle":"$handle",'
      '"issuedAtMs":1750000000000,'
      '"recipientDevicePeerId":"12D3KooWRecipientDevice1","version":1}',
    );
    expect(CallWakeHandleGrant.fromCanonicalMap(value.toCanonicalMap()), value);
  });

  test(
    'strict grammar rejects unknown, missing, mistyped, and unsafe fields',
    () {
      final canonical = grant().toCanonicalMap();
      final invalidValues = <Object?>[
        {...canonical, 'unknown': true},
        <String, Object>{...canonical}..remove('generation'),
        {...canonical, 'version': '1'},
        {...canonical, 'version': 2},
        {...canonical, 'handle': handle.toUpperCase()},
        {...canonical, 'handle': handle.substring(1)},
        {...canonical, 'recipientDevicePeerId': 'peer with spaces'},
        {...canonical, 'deviceKeyEpoch': 0},
        {...canonical, 'generation': 0},
        {...canonical, 'expiresAtMs': canonical['issuedAtMs']!},
      ];

      for (final value in invalidValues) {
        expect(
          () => CallWakeHandleGrant.fromCanonicalMap(value),
          throwsFormatException,
          reason: '$value',
        );
      }
    },
  );

  test('validity is half-open and anti-rollback uses monotonic generation', () {
    final value = grant();
    expect(value.isValidAt(value.issuedAtMs - 1), isFalse);
    expect(value.isValidAt(value.issuedAtMs), isTrue);
    expect(value.isValidAt(value.expiresAtMs - 1), isTrue);
    expect(value.isValidAt(value.expiresAtMs), isFalse);

    expect(grant(generation: 4).isStrictlyNewerThan(value), isTrue);
    expect(grant(generation: 3).isStrictlyNewerThan(value), isFalse);
    expect(grant(generation: 2).isStrictlyNewerThan(value), isFalse);
    expect(
      grant(deviceKeyEpoch: 8, generation: 1).isStrictlyNewerThan(value),
      isFalse,
    );
    expect(
      grant(deviceKeyEpoch: 6, generation: 4).isStrictlyNewerThan(value),
      isTrue,
    );
  });
}
