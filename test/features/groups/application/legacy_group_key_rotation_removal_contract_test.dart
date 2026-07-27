import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _ownedDartRoots = <String>[
  'lib',
  'test',
  'integration_test',
  'test_driver',
  'scripts',
  'tool',
  'packages',
];

const _derivedDirectoryNames = <String>{
  '.dart_tool',
  '.git',
  '.idea',
  '.symlinks',
  'build',
};

const _contractPath =
    'test/features/groups/application/'
    'legacy_group_key_rotation_removal_contract_test.dart';

void main() {
  final repository = Directory.current.absolute;

  test('DTR10-ROT-01 removes only the Dart legacy rotation leaf', () {
    const retiredSource =
        'lib/features/groups/application/rotate_group_key_use_case.dart';
    const retiredTest =
        'test/features/groups/application/rotate_group_key_use_case_test.dart';
    const retiredSourceName = 'rotate_group_key_use_case.dart';
    const retiredEntryPoint = 'rotateGroupKey';
    const retiredHelper = 'callGroupRotateKey';
    const retainedNativeMethod = 'groupRotateKey';
    const retiredRawCommand = 'group:rotateKey';

    expect(
      _file(repository, retiredSource).existsSync(),
      isFalse,
      reason: 'the obsolete Dart rotation source must stay retired',
    );
    expect(
      _file(repository, retiredTest).existsSync(),
      isFalse,
      reason: 'the obsolete source-only suite must stay retired',
    );

    final manifest = _read(repository, 'tool/runtime_roots/runtime_roots.json');
    expect(
      manifest,
      isNot(contains(retiredSource)),
      reason: 'runtime-root metadata must match the retired source tree',
    );

    final groupGate = _read(repository, 'scripts/run_test_gates.sh');
    expect(
      groupGate,
      contains(_contractPath),
      reason: 'the groups gate must own the removal contract',
    );
    expect(
      groupGate,
      isNot(contains(retiredTest)),
      reason: 'the groups gate must not select the deleted suite',
    );

    final retiredEntryPointToken = _wholeIdentifier(retiredEntryPoint);
    final retiredHelperToken = _wholeIdentifier(retiredHelper);
    final directNativeMethodToken = _wholeIdentifier(retainedNativeMethod);
    final tokenHits = <String>[];
    final sourcePathHits = <String>[];
    final rawProductionHits = <String>[];

    for (final file in _ownedDartFiles(repository)) {
      final relativePath = _relativePath(repository, file);
      if (relativePath == _contractPath) {
        continue;
      }
      final contents = file.readAsStringSync();
      if (retiredEntryPointToken.hasMatch(contents) ||
          retiredHelperToken.hasMatch(contents) ||
          directNativeMethodToken.hasMatch(contents)) {
        tokenHits.add(relativePath);
      }
      if (contents.contains(retiredSourceName)) {
        sourcePathHits.add(relativePath);
      }
      if (relativePath.startsWith('lib/') &&
          (contents.contains("'$retiredRawCommand'") ||
              contents.contains('"$retiredRawCommand"'))) {
        rawProductionHits.add(relativePath);
      }
    }

    expect(
      tokenHits,
      isEmpty,
      reason:
          'retired entry points, helpers, and direct native-method bypasses '
          'must have no owned-Dart residue',
    );
    expect(
      sourcePathHits,
      isEmpty,
      reason: 'the retired source must not be imported or exported',
    );
    expect(
      rawProductionHits,
      isEmpty,
      reason: 'production Dart must not retain the retired raw command',
    );

    final currentDocs = <String, String>{
      for (final path in const <String>[
        'C4/file-structure.md',
        'C4/code.md',
        'C4/components.md',
        'C4/infrastructure.md',
      ])
        path: _read(repository, path),
    };
    final combinedDocs = currentDocs.values.join('\n');

    expect(
      currentDocs['C4/file-structure.md'],
      isNot(contains(retiredSourceName)),
      reason: 'current file structure still advertises the retired source',
    );
    expect(
      retiredEntryPointToken.hasMatch(combinedDocs),
      isFalse,
      reason: 'current C4 still advertises the retired Dart entry point',
    );
    expect(
      retiredHelperToken.hasMatch(combinedDocs),
      isFalse,
      reason: 'current C4 still advertises the retired Dart helper',
    );
    expect(
      currentDocs['C4/code.md'],
      isNot(contains('group:rotateKey   → groupRotateKey')),
      reason: 'current C4 code still advertises the retired Dart mapping',
    );
    expect(
      currentDocs['C4/components.md'],
      isNot(contains('group:rotateKey')),
      reason: 'current C4 components still advertises the retired Dart mapping',
    );
    expect(
      currentDocs['C4/infrastructure.md'],
      isNot(contains('| `group:rotateKey` | `groupRotateKey` |')),
      reason:
          'current command-registry table still advertises the retired '
          'Dart mapping',
    );
    expect(
      combinedDocs,
      isNot(contains('handleGroupRotateKey')),
      reason: 'current C4 must not retain a nonexistent Go handler claim',
    );
    expect(
      combinedDocs,
      isNot(contains('Node.GroupRotateKey')),
      reason: 'current C4 must not retain a nonexistent Node method claim',
    );

    for (final retainedDocAnchor in const <String>[
      'rotateAndDistributeGroupKey',
      'groupRotateKey',
      'BridgeGroupRotateKey',
      'GroupRotateKey',
      'LEGACY_ROTATE_KEY_UNSUPPORTED',
    ]) {
      expect(
        combinedDocs,
        contains(retainedDocAnchor),
        reason:
            'current C4 must retain the compatibility/live-flow anchor '
            '$retainedDocAnchor',
      );
    }

    final testInventory = _read(
      repository,
      'Test-Flight-Improv/codebase-test-inventory.md',
    );
    expect(
      testInventory,
      isNot(contains('rotate_group_key_use_case_test.dart')),
      reason: 'the current test inventory still lists the deleted suite',
    );
    expect(
      testInventory,
      contains('rotate_and_distribute_group_key_use_case_test.dart'),
      reason: 'the current test inventory must retain the live rotation suite',
    );
    expect(
      testInventory,
      contains('legacy_group_key_rotation_removal_contract_test.dart'),
      reason: 'the current test inventory must list this removal contract',
    );

    final retainedFiles = <String, List<String>>{
      'android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt': <String>[
        '"groupRotateKey" ->',
        'GoMknoon.groupRotateKey',
      ],
      'ios/Runner/GoBridge.swift': <String>[
        'case "groupRotateKey":',
        'BridgeGroupRotateKey',
      ],
      'macos/Runner/MainFlutterWindow.swift': <String>[
        'case "groupRotateKey":',
        'BridgeGroupRotateKey',
      ],
      'go-mknoon/bridge/bridge.go': <String>[
        'func GroupRotateKey(',
        'LEGACY_ROTATE_KEY_UNSUPPORTED',
      ],
      'go-mknoon/bridge/bridge_test.go': <String>[
        'TestGroupRotateKey_KE014FailsClosedWithoutMutatingStoredKeyState',
      ],
      'lib/features/groups/application/'
          'rotate_and_distribute_group_key_use_case.dart': <String>[
        'Future<RotateGroupKeyOutcome> rotateAndDistributeGroupKey(',
        'callGroupGenerateNextKey',
        'callGroupUpdateKey',
      ],
      'lib/main.dart': <String>[
        'rotateGroupKeyAfterRemoteRemoval:',
        'rotateAndDistributeGroupKey(',
      ],
      'test/features/groups/application/'
          'remove_group_member_use_case_test.dart': <String>[
        'does NOT call group:rotateKey',
      ],
    };

    for (final entry in retainedFiles.entries) {
      final contents = _read(repository, entry.key);
      for (final anchor in entry.value) {
        expect(
          contents,
          contains(anchor),
          reason: 'retained boundary missing ${entry.key}: $anchor',
        );
      }
    }
  });
}

File _file(Directory repository, String relativePath) {
  return File(
    '${repository.path}${Platform.pathSeparator}'
    '${relativePath.replaceAll('/', Platform.pathSeparator)}',
  );
}

String _read(Directory repository, String relativePath) {
  final file = _file(repository, relativePath);
  if (!file.existsSync()) {
    throw StateError('Required repository file is missing: $relativePath');
  }
  return file.readAsStringSync();
}

RegExp _wholeIdentifier(String identifier) {
  return RegExp(
    '(?:^|[^A-Za-z0-9_])${RegExp.escape(identifier)}'
    r'(?:$|[^A-Za-z0-9_])',
    multiLine: true,
  );
}

List<File> _ownedDartFiles(Directory repository) {
  final result = <File>[];
  for (final root in _ownedDartRoots) {
    final directory = Directory(
      '${repository.path}${Platform.pathSeparator}$root',
    );
    if (!directory.existsSync()) {
      throw StateError('Required owned Dart root is missing: $root');
    }
    _collectDartFiles(directory, result);
  }
  for (final entity in repository.listSync(followLinks: false)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      result.add(entity);
    }
  }
  result.sort((left, right) => left.path.compareTo(right.path));
  return result;
}

void _collectDartFiles(Directory directory, List<File> result) {
  for (final entity in directory.listSync(followLinks: false)) {
    if (entity is Link) {
      continue;
    }
    if (entity is Directory) {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (!_derivedDirectoryNames.contains(name)) {
        _collectDartFiles(entity, result);
      }
      continue;
    }
    if (entity is File && entity.path.endsWith('.dart')) {
      result.add(entity);
    }
  }
}

String _relativePath(Directory repository, File file) {
  final prefix = '${repository.path}${Platform.pathSeparator}';
  return file.path
      .substring(prefix.length)
      .replaceAll(Platform.pathSeparator, '/');
}
