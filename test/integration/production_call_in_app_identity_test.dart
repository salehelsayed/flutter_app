import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/production_call_in_app_identity.dart';

const _package = 'com.example.call';
const _peers = ['peer-one-private', 'peer-two-private'];
const _name = 'Fixture caller';
String _digest(String value) => sha256.convert(utf8.encode(value)).toString();

String _xml(
  String phase, {
  String name = _name,
  String packageName = _package,
  String extra = '',
  String outside = '',
  bool hiddenName = false,
}) =>
    '''<hierarchy>
<node package="$packageName" enabled="true" content-desc="Underlying conversation">
$outside
<node package="$packageName" enabled="true" content-desc="Call profile">
<node package="$packageName" enabled="true" visible-to-user="${!hiddenName}" content-desc="$name"/>
<node package="$packageName" enabled="true" resource-id="call_status" content-desc="${phase == 'incoming' ? 'Incoming call' : 'Connected'}"/>
$extra
</node></node></hierarchy>''';
Map<String, Object?> _read(String phase, {String name = _name, String? xml}) =>
    productionCallInAppIdentitySnapshot(
      xml ?? _xml(phase, name: name),
      packageName: _package,
      expectedName: name,
      peerIds: _peers,
      phase: phase,
    );

Map<String, Object?> _proof({bool fallback = false}) {
  final name = fallback ? 'Unknown contact' : _name;
  Map<String, Object?> current(String phase) => {
    'sourceBound': true,
    'connectionReadSucceeded': true,
    'inCall': true,
    'callSha256': 'a' * 64,
    'contactSha256': _digest(_peers[1]),
    'direction': 'incoming',
    'state': phase == 'incoming' ? 'ringing' : 'connected',
  };
  return {
    'caseId': fallback ? 'kx0017' : 'kx0016',
    'contactName': {
      'displayNameSha256': fallback ? _digest(_peers[1]) : _digest(_name),
      'readableName': !fallback,
      'contactSha256': _digest(_peers[1]),
      'blocked': false,
    },
    'expectedInAppNameSha256': _digest(name),
    'inAppPackageSha256': _digest(_package),
    'observations': {
      for (final phase in ['incoming', 'connected'])
        phase: {
          'current': current(phase),
          'inAppIdentity': {
            ..._read(phase, name: name),
            'before': current(phase),
            'after': current(phase),
          },
        },
    },
  };
}

List<String> _validate(Map<String, Object?> proof) =>
    validateProductionCallInAppIdentity(
      proof,
      actorIdentity: _digest(_peers[0]),
      otherIdentity: _digest(_peers[1]),
    );

void main() {
  test(
    'identity and stage copy match the actual shipped English Flutter labels',
    () {
      final english =
          jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map;
      expect(english['call_unknown_contact'], 'Unknown contact');
      expect(english['call_status_incoming'], 'Incoming call');
      expect(english['call_status_connected'], 'Connected');
    },
  );
  test(
    'readable owned Flutter names are bound to the same incoming and connected call',
    () {
      expect(_validate(_proof()), isEmpty);
    },
  );
  test('safe Flutter fallback differs from the native card fallback', () {
    expect(_validate(_proof(fallback: true)), isEmpty);
  });
  test(
    'a visible disabled control containing either actual peer ID is still a privacy leak',
    () {
      final xml = _xml(
        'incoming',
        extra:
            '<node package="$_package" enabled="false" content-desc="${_peers[0]}"/>',
      );
      expect(_read('incoming', xml: xml)['peerIdVisible'], isTrue);
    },
  );
  test('hidden ancestor content is not a visible peer-ID disclosure', () {
    final xml = _xml(
      'incoming',
      extra:
          '<node package="$_package" visible-to-user="false"><node package="$_package" enabled="true" content-desc="${_peers[0]}"/></node>',
    );
    expect(_read('incoming', xml: xml)['peerIdVisible'], isFalse);
  });
  test(
    'a foreign native window cannot stand in for the owned Flutter call',
    () {
      final value = _read(
        'incoming',
        xml: _xml('incoming', packageName: 'com.example.foreign'),
      );
      expect(value['ownedStatusNodeCount'], 0);
      expect(value['nameNodeCount'], 0);
    },
  );
  test('a hidden name is not readable foreground identity', () {
    expect(
      _read(
        'incoming',
        xml: _xml('incoming', hiddenName: true),
      )['nameNodeCount'],
      0,
    );
  });
  test(
    'an authenticated contact name in the underlying chat cannot mask the wrong call name',
    () {
      final xml = _xml(
        'incoming',
        name: 'Wrong call name',
        outside:
            '<node package="$_package" enabled="true" content-desc="$_name"/>',
      );
      expect(_read('incoming', xml: xml)['nameNodeCount'], 0);
    },
  );
  test(
    'UI from a replacement call between the actual current snapshots is rejected',
    () {
      final proof = _proof();
      ((((proof['observations'] as Map)['connected'] as Map)['inAppIdentity']
                  as Map)['after']
              as Map)['callSha256'] =
          'b' * 64;
      expect(_validate(proof), isNotEmpty);
    },
  );
  test('wrong package evidence cannot be rebound to the expected app', () {
    final proof = _proof();
    (((proof['observations'] as Map)['incoming'] as Map)['inAppIdentity']
        as Map)['packageSha256'] = _digest(
      'com.example.foreign',
    );
    expect(_validate(proof), isNotEmpty);
  });
  test('the incoming and active Flutter legs are both required', () {
    final proof = _proof();
    ((proof['observations'] as Map)['incoming'] as Map).remove('inAppIdentity');
    expect(_validate(proof), isNotEmpty);
  });
  test('native MKnoon caller copy cannot certify the Flutter fallback', () {
    final proof = _proof(fallback: true);
    proof['expectedInAppNameSha256'] = _digest('MKnoon caller');
    expect(_validate(proof), isNotEmpty);
  });
  test('multiple apparent call status nodes are ambiguous', () {
    final xml = _xml(
      'incoming',
      extra:
          '<node package="$_package" enabled="true" resource-id="call_status" content-desc="Incoming call"/>',
    );
    expect(_read('incoming', xml: xml)['ownedStatusNodeCount'], 2);
  });
  test(
    'a privacy observation must check the two actual distinct authenticated peers',
    () {
      expect(
        () => productionCallInAppIdentitySnapshot(
          _xml('incoming'),
          packageName: _package,
          expectedName: _name,
          peerIds: [_peers[0], _peers[0]],
          phase: 'incoming',
        ),
        throwsArgumentError,
      );
      final proof = _proof();
      (((proof['observations'] as Map)['connected'] as Map)['inAppIdentity']
          as Map)['peerSha256s'] = [
        _digest('unrelated-one'),
        _digest('unrelated-two'),
      ];
      expect(_validate(proof), isNotEmpty);
    },
  );
}
