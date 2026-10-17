import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// SE-42 D27: the `relay:reconnect` answer decides whether the caller counts
/// a failure. Go answers CALL_MEDIA_PROTECTED and RECOVERY_SUPERSEDED when it
/// kept its host on purpose; those are not failures of this path.
void main() {
  const cases = <String, (Map<String, Object?>, RelayReconnectOutcome)>{
    'success true': (
      {'ok': true, 'success': true, 'recoveryMode': 'in_place'},
      RelayReconnectOutcome.recovered,
    ),
    'absent success (older bridge)': (
      {'ok': true, 'recoveryMode': 'in_place'},
      RelayReconnectOutcome.recovered,
    ),
    'call media protected': (
      {
        'ok': true,
        'success': false,
        'recoveryMode': 'in_place',
        'errorCode': 'CALL_MEDIA_PROTECTED',
      },
      RelayReconnectOutcome.heldInPlace,
    ),
    'recovery superseded': (
      {
        'ok': true,
        'success': false,
        'recoveryMode': 'in_place',
        'errorCode': 'RECOVERY_SUPERSEDED',
      },
      RelayReconnectOutcome.heldInPlace,
    ),
    'in-place refresh failed': (
      {
        'ok': true,
        'success': false,
        'recoveryMode': 'in_place',
        'errorCode': 'REFRESH_FAILED',
      },
      RelayReconnectOutcome.failed,
    ),
    'restart without circuit': (
      {
        'ok': true,
        'success': false,
        'recoveryMode': 'watchdog_restart',
        'errorCode': 'NO_CIRCUIT',
      },
      RelayReconnectOutcome.failed,
    ),
    'bridge error': (
      {'ok': false, 'errorCode': 'RELAY_ERROR'},
      RelayReconnectOutcome.failed,
    ),
    'bridge error wearing a held code': (
      {'ok': false, 'errorCode': 'CALL_MEDIA_PROTECTED'},
      RelayReconnectOutcome.failed,
    ),
  };

  for (final entry in cases.entries) {
    test('classifies ${entry.key}', () {
      final (response, expected) = entry.value;
      expect(
        classifyRelayReconnect(Map<String, dynamic>.from(response)),
        expected,
      );
    });
  }
}
