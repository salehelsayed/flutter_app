import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/group_multi_device_real_harness.dart';

void main() {
  tearDown(() {
    setGroupMultiDeviceRuntimeSharedDir(null);
  });

  test('shared signal helpers use runtime shared directory override', () {
    final dir = Directory.systemTemp.createTempSync(
      'gmd_shared_dir_override_test_',
    );
    addTearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });
    final proofName =
        'proof_${pid}_${DateTime.now().microsecondsSinceEpoch}.txt';

    setGroupMultiDeviceRuntimeSharedDir(dir.path);

    expect(groupMultiDeviceRuntimeSharedDir(), dir.path);
    expect(sharedPath(proofName), '${dir.path}/$proofName');

    writeSharedText(proofName, 'ok');

    expect(File('${dir.path}/$proofName').readAsStringSync(), 'ok');
    expect(File('/tmp/$proofName').existsSync(), isFalse);
  });

  test(
    'Android harness acquires the canonical runtime before Go bridge use',
    () {
      final source = File(
        'integration_test/group_multi_device_real_harness.dart',
      ).readAsStringSync();
      final leaseDeclaration = source.indexOf(
        'final runtimeLease = CanonicalRuntimeDeviceTestLease(',
      );
      final leaseAcquire = source.indexOf(
        'setUpAll(runtimeLease.acquire);',
        leaseDeclaration,
      );
      final scenarioTest = source.indexOf(
        "testWidgets(\n    'MD-004 multi-device proof",
        leaseAcquire,
      );

      expect(
        source,
        contains("import '_support/canonical_runtime_device_test_lease.dart';"),
      );
      expect(leaseDeclaration, isNonNegative);
      expect(leaseAcquire, greaterThan(leaseDeclaration));
      expect(scenarioTest, greaterThan(leaseAcquire));
      expect(source, contains('tearDownAll(runtimeLease.release);'));
    },
  );
}
