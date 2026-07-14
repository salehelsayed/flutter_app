import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/android_picture_in_picture_system_ui_selection_result.dart';

void main() {
  const validator =
      'scripts/validate_android_picture_in_picture_system_ui_selection.py';
  late Directory temporaryDirectory;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'mknoon-android-pip-selection-',
    );
  });

  tearDown(() {
    temporaryDirectory.deleteSync(recursive: true);
  });

  test('atomic structured result round trips through the exact schema', () {
    final output = File('${temporaryDirectory.path}/selection.json');
    const selection = AndroidPictureInPictureSystemUiSelectionResult(
      selectorSource: 'resource-id',
      resourceId: 'com.android.systemui:id/expand_button',
      contentDescription: 'Full screen',
      bounds: <int>[405, 1586, 517, 1698],
      center: <int>[461, 1642],
      geometryEvidence: '',
    );

    selection.writeAtomic(output);
    final decoded = AndroidPictureInPictureSystemUiSelectionResult.parseExact(
      output.readAsStringSync(),
    );

    expect(decoded.selectorSource, 'resource-id');
    expect(decoded.bounds, <int>[405, 1586, 517, 1698]);
    expect(decoded.center, <int>[461, 1642]);
    expect(
      () => selection.writeAtomic(output),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('retry-5 capture validates independently of contaminated stdout', () {
    final structured = File(
      'test/fixtures/android_picture_in_picture_retry5_selection.json',
    );
    final contaminatedStdout = File(
      'test/fixtures/android_picture_in_picture_retry5_selector_stdout.txt',
    ).readAsStringSync();
    final normalized = File('${temporaryDirectory.path}/normalized.txt');

    expect(
      () => AndroidPictureInPictureSystemUiSelectionResult.parseExact(
        contaminatedStdout,
      ),
      throwsFormatException,
    );
    final result = Process.runSync('python3', <String>[
      validator,
      structured.path,
      normalized.path,
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(
      normalized.readAsLinesSync(),
      containsAllInOrder(<String>[
        'selectorSource=pixel6-api36-wmshell-geometry',
        'bounds=389 2002 910 2295',
        'center=649 2148',
      ]),
    );
  });

  for (final invalid in <String, String>{
    'malformed': '{',
    'missing':
        '{"schema":"mknoon.android-pip-system-ui-control.v1",'
        '"selectorSource":"resource-id"}',
    'duplicate':
        '{"schema":"mknoon.android-pip-system-ui-control.v1",'
        '"schema":"mknoon.android-pip-system-ui-control.v1",'
        '"selectorSource":"resource-id","resourceId":"id",'
        '"contentDescription":"Full screen","bounds":[0,0,10,10],'
        '"center":[5,5],"geometryEvidence":""}',
  }.entries) {
    test('validator rejects ${invalid.key} structured result', () {
      final input = File('${temporaryDirectory.path}/${invalid.key}.json')
        ..writeAsStringSync(invalid.value);
      final normalized = File(
        '${temporaryDirectory.path}/${invalid.key}-normalized.txt',
      );

      final result = Process.runSync('python3', <String>[
        validator,
        input.path,
        normalized.path,
      ]);

      expect(result.exitCode, 3);
      expect(normalized.existsSync(), isFalse);
    });
  }

  test('validator rejects a symlink instead of following it', () {
    final target = File('${temporaryDirectory.path}/target.json')
      ..writeAsStringSync(
        File(
          'test/fixtures/android_picture_in_picture_retry5_selection.json',
        ).readAsStringSync(),
      );
    final input = Link('${temporaryDirectory.path}/selection-link.json')
      ..createSync(target.path);
    final normalized = File('${temporaryDirectory.path}/normalized.txt');

    final result = Process.runSync('python3', <String>[
      validator,
      input.path,
      normalized.path,
    ]);

    expect(result.exitCode, 3);
    expect(normalized.existsSync(), isFalse);
  });
}
