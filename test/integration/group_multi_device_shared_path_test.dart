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
}
