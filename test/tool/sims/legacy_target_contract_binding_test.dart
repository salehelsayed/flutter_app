import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../../tool/sims/device_binding.dart';
import '../../../tool/sims/live_device_resolver.dart';
import '../../../tool/sims/manifest.dart';
import '../../../tool/sims/planner.dart';

void main() {
  final manifest = SimsManifest.loadSync(
    File(
      Platform.environment['MKNOON_CLOSURE_SIMS_MANIFEST'] ??
          'tool/sims/critical_features.json',
    ),
  );
  final row = manifest.capabilityById('reliability.full.cleaned_legacy')!;
  SimsDevicePlanBinding bind(CapabilitySpec row, Map<String, String> env) =>
      SimsDevicePlanBinding.bind(
        SimsPlan(
          mode: SimsMode.full,
          simultaneous: false,
          releaseEligibleCandidate: false,
          manifestDigest: 'host-fixture',
          family: null,
          onlyId: row.id,
          rows: [row],
        ),
        SimsLiveDeviceInventory(
          targets: [],
          sourceResults: [
            for (final source in SimsDeviceDiscoverySource.values)
              SimsDiscoverySourceResult(
                source: source,
                status: SimsDiscoveryStatus.success,
                detail: 'synthetic empty inventory',
              ),
          ],
        ),
        processEnvironment: env,
      );
  test(
    'configured cleaned adapter reaches per-route ownership rather than unknown blanket rejection',
    () {
      final result = bind(row, {
        'SIMS_PROTECTED_DEVICE_ASSIGNMENTS_JSON': '{}',
        'MKNOON_LEGACY_ISOLATED': '1',
      });
      expect(result.preflightVerdicts, isEmpty);
      expect(result.preparationTargets, isEmpty);
      expect(
        result.assignments,
        isEmpty,
      ); // Adapter, not this host row, acquires each lease.
    },
  );
  test('missing protected isolated configuration remains blocked', () {
    for (final env in <Map<String, String>>[
      {},
      {'SIMS_PROTECTED_DEVICE_ASSIGNMENTS_JSON': '{}'},
    ]) {
      expect(
        bind(row, env).preflightVerdicts[row.id]?.toJson()['status'],
        'BLOCKED',
      );
    }
  });
  test('unknown device owners retain the original fail-closed guard', () {
    final unknown = row.copyWith(
      resources: [
        const ResourceLock(name: 'unknown', access: ResourceAccess.exclusive),
      ],
    );
    expect(
      bind(unknown, {
        'SIMS_PROTECTED_DEVICE_ASSIGNMENTS_JSON': '{}',
        'MKNOON_LEGACY_ISOLATED': '1',
      }).preflightVerdicts[row.id]?.toJson()['status'],
      'BLOCKED',
    );
  });
}
