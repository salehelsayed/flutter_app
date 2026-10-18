import 'dart:io';

import 'package:flutter_app/debug/production_journeys/sims_runtime_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/android_app_state_guard.dart';
import '../../integration_test/support/production_journey_peer.dart';

/// Answers `getprop ro.build.version.sdk` with [sdk]; rejects the grant the
/// way Android 8.1's `pm` does when the permission predates the platform.
final class _Device implements AndroidHostProcessRunner {
  _Device(this.sdk);
  final String sdk;
  final calls = <List<String>>[];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    expect(executable, 'adb');
    calls.add(arguments);
    if (arguments.contains('getprop')) {
      return ProcessResult(0, 0, '$sdk\n', '');
    }
    if (arguments.contains('grant') && int.parse(sdk) < 33) {
      return ProcessResult(0, 1, '', 'Unknown permission');
    }
    return ProcessResult(0, 0, '', '');
  }
}

ProductionJourneyPeer _peer(_Device device) => ProductionJourneyPeer(
  'fixture-phone',
  const SimsRuntimeInvocation(
    schema: simsRuntimeConfigSchema,
    profileId: 'android.e2e.production',
    scenarioId: 'fixture',
    role: 'alice',
    runId: 'run-1',
    nonce: 'nonce-1',
    values: <String, Object?>{},
  ),
  Directory.systemTemp,
  device,
  packageName: 'com.mknoon.sims.connectivity',
);

void main() {
  test('API 33+ grants POST_NOTIFICATIONS', () async {
    final device = _Device('34');
    await _peer(device).grantPostNotifications();
    expect(device.calls.last, [
      '-s',
      'fixture-phone',
      'shell',
      'pm',
      'grant',
      'com.mknoon.sims.connectivity',
      'android.permission.POST_NOTIFICATIONS',
    ]);
  });

  test('below API 33 the permission does not exist, so no grant is sent', () async {
    final device = _Device('27');
    await _peer(device).grantPostNotifications();
    expect(device.calls.where((c) => c.contains('grant')), isEmpty);
  });

  test('an unreadable SDK level is an error, not a skipped grant', () async {
    final device = _Device('unknown');
    await expectLater(_peer(device).grantPostNotifications(), throwsStateError);
  });
}
