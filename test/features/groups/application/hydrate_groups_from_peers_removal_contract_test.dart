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

void main() {
  final repository = Directory.current.absolute;

  test(
    'DTR10-HYDRATE-01 duplicate hydrate wrapper and bookkeeping are absent',
    () {
      final retiredFileName = <String>[
        'hydrate_groups_from_',
        'peers_use_case.dart',
      ].join();
      final retiredSource = 'lib/features/groups/application/$retiredFileName';
      final retiredTest = <String>[
        'test/features/groups/application/',
        'hydrate_groups_from_',
        'peers_use_case_test.dart',
      ].join();
      final retiredEntryPoint = <String>['hydrateGroups', 'FromPeers'].join();

      expect(
        _file(repository, retiredSource).existsSync(),
        isFalse,
        reason: 'the duplicate hydrate wrapper must stay retired',
      );
      expect(
        _file(repository, retiredTest).existsSync(),
        isFalse,
        reason: 'the wrapper-only suite must stay retired',
      );
      expect(
        _read(repository, 'tool/runtime_roots/runtime_roots.json'),
        isNot(contains(retiredSource)),
        reason: 'runtime-root metadata must match the final source tree',
      );

      final retiredToken = _wholeIdentifier(retiredEntryPoint);
      final tokenHits = <String>[];
      final sourcePathHits = <String>[];
      for (final file in _ownedDartFiles(repository)) {
        final contents = file.readAsStringSync();
        final relativePath = _relativePath(repository, file);
        if (retiredToken.hasMatch(contents)) {
          tokenHits.add(relativePath);
        }
        if (contents.contains(retiredFileName)) {
          sourcePathHits.add(relativePath);
        }
      }
      expect(
        tokenHits,
        isEmpty,
        reason:
            'the retired identifier must have no declaration, call, tear-off, '
            'fake, or other owned-Dart residue',
      );
      expect(
        sourcePathHits,
        isEmpty,
        reason:
            'the retired source must not be imported or exported through '
            'either a package or relative URI',
      );

      final lifecycleGuard = _read(
        repository,
        'test/features/groups/application/'
        'self_removed_group_lifecycle_guard_test.dart',
      );
      expect(
        lifecycleGuard,
        contains(
          'marked shells and loaded membership work perform zero join inbox '
          'announce dissolve or pending sends',
        ),
        reason: 'the renamed lifecycle preservation selector must remain',
      );
      expect(
        lifecycleGuard,
        isNot(
          contains(
            'marked shells and loaded membership work perform zero join inbox '
            'hydrate announce dissolve or pending sends',
          ),
        ),
        reason: 'the lifecycle selector must not retain the retired leaf name',
      );

      for (final path in <String>[
        'lib/features/groups/application/rejoin_group_topics_use_case.dart',
        'lib/features/groups/application/'
            'drain_group_offline_inbox_use_case.dart',
        'test/features/groups/application/'
            'self_removed_group_lifecycle_guard_test.dart',
      ]) {
        expect(
          _file(repository, path).existsSync(),
          isTrue,
          reason: 'live recovery anchor must remain: $path',
        );
      }
    },
  );
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
