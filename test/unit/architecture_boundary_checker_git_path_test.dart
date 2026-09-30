import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/architecture_guard/architecture_boundary_checker.dart';

void main() {
  test('preserves literal glob punctuation in NUL-delimited Git paths', () {
    final root = Directory.systemTemp.createTempSync('dtr12-git-literal-');
    addTearDown(() => root.deleteSync(recursive: true));
    final gitInit = Process.runSync('git', <String>[
      'init',
      '-q',
    ], workingDirectory: root.path);
    expect(gitInit.exitCode, 0, reason: '${gitInit.stderr}');

    const relativePath =
        'artifacts/T21 accepts the new invite/screen-hierarchy/'
        'step-035-assertCondition-[0-9]+_items_pending.json';
    final file = File(p.join(root.path, relativePath))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{}');

    final paths = ArchitectureBoundaryChecker.listGitVisiblePaths(root.path);

    expect(file.existsSync(), isTrue);
    expect(paths.visible, contains(relativePath));
  });
}
