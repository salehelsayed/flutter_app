import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _ownedDartRoots = <String>[
  'lib',
  'test',
  'integration_test',
  'test_driver',
  'tool',
  'packages',
  'scripts',
];

const _currentArchitectureDocs = <String>[
  'C4/file-structure.md',
  'C4/code.md',
  'C4/components.md',
];

const _derivedDirectoryNames = <String>{
  '.dart_tool',
  '.git',
  '.idea',
  '.symlinks',
  'build',
};

void main() {
  final repository = Directory.current.absolute;

  test('DTR10-JOIN-01 old direct join island and bookkeeping are absent', () {
    final retiredSource = <String>[
      'lib/features/groups/application/',
      'join_',
      'group_use_case.dart',
    ].join();
    final retiredTest = <String>[
      'test/features/groups/application/',
      'join_',
      'group_use_case_test.dart',
    ].join();
    final retiredEntryPoint = <String>['join', 'Group'].join();
    final retiredRepositoryMethod = <String>[
      'commitFresh',
      'DirectJoin',
    ].join();

    expect(
      _file(repository, retiredSource).existsSync(),
      isFalse,
      reason: 'the obsolete direct-join source must stay retired',
    );
    expect(
      _file(repository, retiredTest).existsSync(),
      isFalse,
      reason: 'the obsolete direct-join SUT-only suite must stay retired',
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
      isNot(contains(retiredTest)),
      reason: 'the groups gate must not select the deleted suite',
    );

    final retiredEntryPointToken = _wholeIdentifier(retiredEntryPoint);
    final retiredRepositoryToken = _wholeIdentifier(retiredRepositoryMethod);
    final tokenHits = <String>[];
    final importHits = <String>[];
    for (final file in _ownedDartFiles(repository)) {
      final contents = file.readAsStringSync();
      final relativePath = _relativePath(repository, file);
      if (retiredEntryPointToken.hasMatch(contents) ||
          retiredRepositoryToken.hasMatch(contents)) {
        tokenHits.add(relativePath);
      }
      if (contents.contains(retiredSource)) {
        importHits.add(relativePath);
      }
    }

    expect(
      tokenHits,
      isEmpty,
      reason:
          'retired direct-join identifiers must have no declaration, call, '
          'tear-off, fake, or other owned-Dart residue',
    );
    expect(
      importHits,
      isEmpty,
      reason: 'the retired direct-join source must not be imported or exported',
    );

    for (final path in <String>[
      'lib/features/groups/application/'
          'accept_pending_group_invite_use_case.dart',
      'lib/features/groups/application/'
          'handle_incoming_group_invite_use_case.dart',
      'lib/features/groups/application/rejoin_group_topics_use_case.dart',
      'lib/core/bridge/bridge_group_helpers.dart',
    ]) {
      expect(
        _file(repository, path).existsSync(),
        isTrue,
        reason: 'live full-config join anchor must remain: $path',
      );
    }

    expect(
      _read(
        repository,
        'lib/features/groups/domain/repositories/group_repository.dart',
      ),
      contains('retryAcceptedReentryNative'),
      reason: 'the live accepted-reentry coordinator contract must remain',
    );

    for (final path in _currentArchitectureDocs) {
      final contents = _read(repository, path);
      expect(
        contents.contains(retiredSource),
        isFalse,
        reason: '$path still advertises the retired source',
      );
      expect(
        retiredEntryPointToken.hasMatch(contents),
        isFalse,
        reason: '$path still advertises the retired entry point',
      );
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
