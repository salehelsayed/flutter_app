import 'dart:io';

import 'package:flutter_app/core/debug/auto_setup_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('auto_setup_config_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('resolves username from auto setup config file', () async {
    await File(
      '${tempDir.path}/$autoSetupConfigFileName',
    ).writeAsString('{"username":"a"}\n');

    expect(await resolveAutoSetupUsername(tempDir.path), 'a');
  });

  test('trims username from config file', () async {
    await File(
      '${tempDir.path}/$autoSetupConfigFileName',
    ).writeAsString('{"username":"  b  "}\n');

    expect(await resolveAutoSetupUsername(tempDir.path), 'b');
  });

  test('returns null when config file is absent', () async {
    expect(await resolveAutoSetupUsername(tempDir.path), isNull);
  });

  test('returns null for malformed config file', () async {
    await File(
      '${tempDir.path}/$autoSetupConfigFileName',
    ).writeAsString('{not-json');

    expect(await resolveAutoSetupUsername(tempDir.path), isNull);
  });

  test('returns null for missing or blank username', () async {
    final file = File('${tempDir.path}/$autoSetupConfigFileName');

    await file.writeAsString('{"other":"a"}\n');
    expect(await resolveAutoSetupUsername(tempDir.path), isNull);

    await file.writeAsString('{"username":"   "}\n');
    expect(await resolveAutoSetupUsername(tempDir.path), isNull);
  });
}
