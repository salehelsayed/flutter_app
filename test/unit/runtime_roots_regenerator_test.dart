import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/runtime_roots/regenerate_runtime_roots.dart';

void main() {
  test(
    'preview and write repair moved evidence while preserving review values',
    () {
      final manifest = _manifest();
      final originalRow = _external('scripts/reviewed.dart')
        ..['owner'] = 'Reviewed owner'
        ..['reason'] = 'Reviewed reason'
        ..['condition'] = 'Reviewed removal condition'
        ..['seedsTooling'] = true
        ..['reviewTicket'] = <String, Object?>{'id': 42}
        ..['evidence'] = <Object?>[
          <String, Object?>{
            'kind': 'json-value',
            'source': 'tool/sims/critical_features.json',
            'keyPath': 'capabilities.0.command.1',
            'value': 'scripts/reviewed.dart',
          },
        ];
      (manifest['externalEntrypoints'] as List).add(originalRow);
      final fixture = _Fixture(manifest, <String, String>{
        'scripts/reviewed.dart': _entrypoint,
        'tool/sims/critical_features.json': jsonEncode(<String, Object?>{
          'capabilities': <Object?>[
            <String, Object?>{
              'command': <String>['dart', 'unrelated.dart'],
            },
            <String, Object?>{
              'command': <String>['dart', 'scripts/reviewed.dart'],
            },
            <String, Object?>{
              'command': <String>['dart', 'scripts/reviewed.dart'],
            },
          ],
        }),
      });
      addTearDown(fixture.dispose);
      final before = fixture.manifestFile.readAsStringSync();

      final preview = fixture.regenerate();
      expect(preview.exitCode, 0);
      expect(preview.written, isFalse);
      expect(fixture.manifestFile.readAsStringSync(), before);
      expect(preview.changes.single['matchingLocations'], 2);
      expect(preview.changes.single['to'], 'capabilities.1.command.1');

      final written = fixture.regenerate(write: true);
      expect(written.written, isTrue);
      expect(written.exitCode, 0);
      final expected = jsonDecode(before) as Map<String, dynamic>;
      expected['externalEntrypoints'][0]['evidence'][0]['keyPath'] =
          'capabilities.1.command.1';
      expect(jsonDecode(fixture.manifestFile.readAsStringSync()), expected);

      final once = fixture.manifestFile.readAsStringSync();
      final again = fixture.regenerate(write: true);
      expect(again.changes, isEmpty);
      expect(again.written, isFalse);
      expect(fixture.manifestFile.readAsStringSync(), once);
    },
  );

  test(
    'QA family mains stay non-rooted and other locations still need review',
    () {
      final fixture = _Fixture(_manifest(), <String, String>{
        'integration_test/scripts/new.dart': _entrypoint,
        'scripts/new.dart': _entrypoint,
        'tool/unknown.dart': _entrypoint,
      });
      addTearDown(fixture.dispose);

      final result = fixture.regenerate(write: true);
      expect(result.exitCode, 1);
      expect(result.toJson()['derivedQaEntrypoints'], 2);
      final manifest =
          jsonDecode(fixture.manifestFile.readAsStringSync()) as Map;
      final entries = manifest['externalEntrypoints'] as List;
      expect(entries.map((entry) => entry['path']).toSet(), <String>{
        'integration_test/scripts/new.dart',
        'scripts/new.dart',
      });
      for (final entry in entries) {
        expect(entry, _external(entry['path'] as String));
        expect(entry['seedsTooling'], isFalse);
      }
      expect(
        result.inventory.issues.any(
          (issue) =>
              issue.code == 'unreviewed-external-entrypoint' &&
              issue.path == 'tool/unknown.dart',
        ),
        isTrue,
      );
    },
  );

  test('new VM callback is reported without creating a reviewed root', () {
    final fixture = _Fixture(_manifest(), <String, String>{
      'lib/main.dart': "import 'callback.dart';\nvoid main() {}\n",
      'lib/callback.dart': "@pragma('vm:entry-point')\nvoid newCallback() {}\n",
    });
    addTearDown(fixture.dispose);
    final before = fixture.manifestFile.readAsStringSync();
    final result = fixture.regenerate(write: true);
    expect(result.exitCode, 1);
    expect(result.written, isFalse);
    expect(
      result.inventory.issues.any(
        (issue) => issue.code == 'unreviewed-vm-entrypoint',
      ),
      isTrue,
    );
    expect(fixture.manifestFile.readAsStringSync(), before);
  });

  test(
    'missing exact evidence remains a decision, never a replacement review',
    () {
      final manifest = _manifest();
      (manifest['externalEntrypoints'] as List).add(
        _external('scripts/reviewed.dart')
          ..['owner'] = 'Original owner'
          ..['evidence'] = <Object?>[
            <String, Object?>{
              'kind': 'json-value',
              'source': 'tool/sims/critical_features.json',
              'keyPath': 'capabilities.0.command.1',
              'value': 'scripts/reviewed.dart',
            },
          ],
      );
      final fixture = _Fixture(manifest, <String, String>{
        'scripts/reviewed.dart': _entrypoint,
        'tool/sims/critical_features.json': jsonEncode(<String, Object?>{
          'capabilities': <Object?>[
            <String, Object?>{
              'command': <String>['dart', 'replacement.dart'],
            },
          ],
        }),
      });
      addTearDown(fixture.dispose);
      final before = fixture.manifestFile.readAsStringSync();
      final result = fixture.regenerate(write: true);
      expect(result.exitCode, 1);
      expect(result.changes, isEmpty);
      expect(fixture.manifestFile.readAsStringSync(), before);
    },
  );

  test(
    'fatal source scan cannot write even when QA entries could be derived',
    () {
      final fixture = _Fixture(_manifest(), <String, String>{
        'lib/main.dart': "import 'missing.dart';\nvoid main() {}\n",
        'scripts/new.dart': _entrypoint,
      });
      addTearDown(fixture.dispose);
      final before = fixture.manifestFile.readAsStringSync();
      expect(() => fixture.regenerate(write: true), throwsFormatException);
      expect(fixture.manifestFile.readAsStringSync(), before);
    },
  );

  test('malformed schema cannot overwrite the original manifest', () {
    final fixture = _Fixture(_manifest(), <String, String>{});
    addTearDown(fixture.dispose);
    fixture.manifestFile.writeAsStringSync('{"schemaVersion": "bad"}');
    final before = fixture.manifestFile.readAsStringSync();
    expect(() => fixture.regenerate(write: true), throwsFormatException);
    expect(fixture.manifestFile.readAsStringSync(), before);
  });
}

const _entrypoint =
    "import 'package:fixture_app/common.dart';\nvoid main() {}\n";

Map<String, Object?> _manifest() => <String, Object?>{
  'schemaVersion': 1,
  'manualRoots': <Object?>[],
  'externalEntrypoints': <Object?>[],
  'declarations': <Object?>[],
  'requiredRestrictedRoots': <Object?>[],
  'restrictedRoots': <Object?>[],
};

Map<String, Object?> _external(String path) => <String, Object?>{
  'path': path,
  'owner': 'QA / release',
  'reason':
      'Non-convention Dart main remains visible pending exact invocation ownership.',
  'condition':
      'Remove or reclassify only after its caller and replacement proof are reviewed.',
  'seedsTooling': false,
  'evidence': <Map<String, Object?>>[
    <String, Object?>{'kind': 'dart-main', 'source': path},
  ],
};

class _Fixture {
  _Fixture(Map<String, Object?> manifest, Map<String, String> files)
    : directory = Directory.systemTemp.createTempSync('runtime-regenerator-') {
    for (final entry in <String, String>{
      'pubspec.yaml': 'name: fixture_app\n',
      'lib/main.dart': "import 'common.dart';\nvoid main() {}\n",
      'lib/common.dart': 'class Common {}\n',
      ...files,
    }.entries) {
      final file = File('${directory.path}/${entry.key}');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
    }
    manifestFile.parent.createSync(recursive: true);
    manifestFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
    );
  }

  final Directory directory;

  File get manifestFile =>
      File('${directory.path}/tool/runtime_roots/runtime_roots.json');

  RuntimeRootsRegeneration regenerate({bool write = false}) =>
      regenerateRuntimeRoots(
        repoRoot: directory.path,
        manifestPath: manifestFile.path,
        write: write,
        gitPathLister: (_) =>
            directory
                .listSync(recursive: true, followLinks: false)
                .whereType<File>()
                .map((file) => file.path.substring(directory.path.length + 1))
                .toList()
              ..sort(),
      );

  void dispose() => directory.deleteSync(recursive: true);
}
