import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _ownedDartRoots = <String>[
  'lib',
  'test',
  'integration_test',
  'test_driver',
  'tool',
  'packages',
];

const _currentArchitectureDocs = <String>[
  'file-structure.md',
  'C4_MODEL.md',
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

  test(
    'DTR03-01 duplicate core ChatMessage model and declaration are absent',
    () {
      final retiredPath = <String>[
        'lib/core/services/',
        'chat_',
        'message.dart',
      ].join();
      final activePath = <String>[
        'lib/features/p2p/domain/models/',
        'chat_',
        'message.dart',
      ].join();

      expect(
        _file(repository, retiredPath).existsSync(),
        isFalse,
        reason: 'the duplicate core ChatMessage source must stay retired',
      );
      expect(
        _file(repository, activePath).existsSync(),
        isTrue,
        reason: 'the active feature ChatMessage model must remain',
      );

      final manifest = _read(
        repository,
        'tool/runtime_roots/runtime_roots.json',
      );
      expect(
        manifest,
        isNot(contains(retiredPath)),
        reason: 'the retired source must not remain declared as a runtime root',
      );

      _expectNoCurrentDocMatch(
        repository,
        RegExp(RegExp.escape('core/services/chat_message.dart')),
        'retired core ChatMessage path',
      );
      _expectNoCurrentDocMatch(
        repository,
        RegExp(
          r'chat_message\.dart\s+# '
          r'(?:ChatMessage canonical model|ChatMessage type re-export)',
        ),
        'retired core ChatMessage tree claim',
      );
    },
  );

  test(
    'DTR03-02 hollow core contact listener and SUT-only suite are absent',
    () {
      final retiredSource = <String>[
        'lib/core/services/',
        'contact_request_',
        'listener.dart',
      ].join();
      final retiredTest = <String>[
        'test/core/services/',
        'contact_request_',
        'listener_test.dart',
      ].join();
      final activeSource = <String>[
        'lib/features/contact_request/application/',
        'contact_request_',
        'listener.dart',
      ].join();

      expect(
        _file(repository, retiredSource).existsSync(),
        isFalse,
        reason: 'the hollow core listener must stay retired',
      );
      expect(
        _file(repository, retiredTest).existsSync(),
        isFalse,
        reason: 'the retired listener SUT-only suite must stay retired',
      );
      expect(
        _file(repository, activeSource).existsSync(),
        isTrue,
        reason: 'the production feature listener must remain',
      );

      final productionBootstrapSource = _read(
        repository,
        'lib/app/bootstrap/production_application_bootstrap.dart',
      );
      expect(
        productionBootstrapSource,
        contains(
          <String>[
            'features/contact_request/application/',
            'contact_request_',
            'listener.dart',
          ].join(),
        ),
        reason:
            'the production bootstrap must retain the feature listener import',
      );

      final manifest = _read(
        repository,
        'tool/runtime_roots/runtime_roots.json',
      );
      expect(
        manifest,
        isNot(contains(retiredSource)),
        reason: 'the retired listener must not remain in runtime-root metadata',
      );

      _expectNoCurrentDocMatch(
        repository,
        RegExp(RegExp.escape('core/services/contact_request_listener.dart')),
        'retired core contact-listener path',
      );
      _expectNoCurrentDocMatch(
        repository,
        RegExp(
          r'contact_request_listener\.dart\s+# '
          r'(?:ContactRequestListener: listens to routed contact request '
          r'messages|Stub ContactRequestListener)',
        ),
        'retired core contact-listener tree claim',
      );
    },
  );

  test(
    'DTR03-03 deprecated topic-only group-join API and legacy tests are absent',
    () {
      final helperPath = 'lib/core/bridge/bridge_group_helpers.dart';
      final helperTestPath = 'test/core/bridge/bridge_group_helpers_test.dart';
      final retiredSymbol = <String>['callGroup', 'Join'].join();
      final fullConfigSymbol = <String>['callGroup', 'JoinWithConfig'].join();
      final legacyError = <String>['LEGACY_JOIN_', 'UNSUPPORTED'].join();

      final helper = _read(repository, helperPath);
      final helperTest = _read(repository, helperTestPath);
      final ownedDartFiles = _ownedDartFiles(repository);
      final retiredToken = _wholeIdentifier(retiredSymbol);
      final tokenHits = <String>[];

      for (final file in ownedDartFiles) {
        final contents = file.readAsStringSync();
        if (retiredToken.hasMatch(contents)) {
          tokenHits.add(_relativePath(repository, file));
        }
      }

      expect(
        tokenHits,
        isEmpty,
        reason:
            'the deprecated API must have no declaration, call, tear-off, '
            'export, or other owned-Dart token residue',
      );
      expect(
        helper,
        isNot(contains(legacyError)),
        reason: 'the active helper must not retain the legacy refusal branch',
      );
      expect(
        helperTest,
        isNot(contains(legacyError)),
        reason: 'the active bridge tests must not retain legacy assertions',
      );
      expect(
        helper,
        contains('Future<void> $fullConfigSymbol('),
        reason: 'the full-config helper declaration must remain',
      );
      expect(
        helperTest,
        contains(
          'sends group:join with groupId, groupConfig, groupKey, keyEpoch',
        ),
        reason: 'the full-config payload test must remain',
      );

      _expectNoCurrentDocMatch(
        repository,
        retiredToken,
        'deprecated topic-only group-join API',
      );
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

void _expectNoCurrentDocMatch(
  Directory repository,
  RegExp pattern,
  String description,
) {
  for (final path in _currentArchitectureDocs) {
    final contents = _read(repository, path);
    expect(
      pattern.hasMatch(contents),
      isFalse,
      reason: '$path still claims the $description',
    );
  }
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
