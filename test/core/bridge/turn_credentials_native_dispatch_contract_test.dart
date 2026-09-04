import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('VC2-01 native wrappers are blind no-payload pass-throughs', () {
    final android = File(
      'android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt',
    ).readAsStringSync();
    final ios = File('ios/Runner/GoBridge.swift').readAsStringSync();
    final goBridge = File(
      'go-mknoon/bridge/bridge_turn_credentials.go',
    ).readAsStringSync();

    expect(
      android,
      contains(
        '"relayTurnCredentialsV1" -> runOnBackground({ '
        'GoMknoon.turnCredentialsV1() }, result)',
      ),
    );
    expect(android, isNot(contains('turnCredentialsV1(args')));
    expect(
      ios,
      contains(
        'case "relayTurnCredentialsV1":\n'
        '            runOnBackground({ BridgeTurnCredentialsV1() }, '
        'result: result)',
      ),
    );
    expect(ios, isNot(contains('BridgeTurnCredentialsV1(args')));
    expect(goBridge, contains('func TurnCredentialsV1() (result string)'));
  });
}
