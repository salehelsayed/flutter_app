import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/group_multi_party_device_criteria.dart';

void main() {
  test('--scenario smoke lists the curated smoke scenarios', () async {
    final result = await Process.run('dart', <String>[
      'integration_test/scripts/run_group_multi_party_device_real.dart',
      '--scenario',
      'smoke',
      '--list-scenarios',
    ]);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(
      (result.stdout as String)
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false),
      smokeGroupMultiPartyDeviceScenarioIds,
    );
  });

  test('--scenario slice_b_live lists the two-scenario live gate', () async {
    final result = await Process.run('dart', <String>[
      'integration_test/scripts/run_group_multi_party_device_real.dart',
      '--scenario',
      'slice_b_live',
      '--list-scenarios',
    ]);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(
      (result.stdout as String)
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false),
      sliceBLiveGateGroupMultiPartyDeviceScenarioIds,
    );
  });
}
