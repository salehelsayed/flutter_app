import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import '../../tool/analyzer_guard/analyzer_suppression_ratchet.dart';

void main() {
  test(
    'discovers production unused directives without matching decoys',
    () async {
      final fixture = _GitFixture(
        files: <String, String>{
          '.gitignore': '.dart_tool/\nlib/ignored.dart\n',
          'pubspec.yaml': '''
name: ratchet_root
environment:
  sdk: ^3.9.0
dependencies:
  linked:
    path: packages/linked
dependency_overrides:
  overridden:
    path: third_party/override
''',
          'analysis_options.yaml': '{}\n',
          'lib/root.dart': r'''
// ignore_for_file: unused_import
// ignore_for_file: TYPE = WARNING
// ignore_for_file: type=lint
/// ignore: UNUSED_ELEMENT, avoid_print -- generated explanation
void _rootSuppressed() {}

const stringDecoy = '// ignore: unused_element';
// Ordinary prose says ignore: unused_element, but is not a directive.
/// Ordinary documentation mentions ignore: unused_element.
void visibleRootDeclaration() {}
''',
          'packages/linked/pubspec.yaml': '''
name: linked
environment:
  sdk: ^3.9.0
''',
          'packages/linked/lib/linked.dart': '''
void _linkedSuppressed() {} // ignore: unused_element, avoid_print -- trailing
''',
          'third_party/override/pubspec.yaml': '''
name: overridden
environment:
  sdk: ^3.9.0
''',
          'third_party/override/lib/override.dart': '''
// ignore: UnUsEd_ElEmEnT -- case-insensitive diagnostic
void _overrideSuppressed() {}
''',
          'deep/arbitrary/package/pubspec.yaml': '''
name: arbitrary
environment:
  sdk: ^3.9.0
''',
          'deep/arbitrary/package/lib/arbitrary.dart': '''
// ignore: unused_element
void _arbitrarySuppressed() {}
''',
          'lib/new\nline.dart': '''
// ignore: unused_element
void _newlineSuppressed() {}
''',
          'lib/deleted.dart': '''
// ignore: unused_element
void _deletedSuppressionMustNotSurvive() {}
''',
        },
        packages: const <String, String>{
          'ratchet_root': '',
          'linked': 'packages/linked',
          'overridden': 'third_party/override',
          'arbitrary': 'deep/arbitrary/package',
        },
      );
      addTearDown(fixture.dispose);
      fixture.stageAll();
      fixture.write('lib/ignored.dart', '''
// ignore: unused_element
void _ignoredSuppressionMustNotAppear() {}
''');
      fixture.delete('lib/deleted.dart');

      final result = await fixture.check(_emptyInventory());

      expect(result.trustworthy, isTrue, reason: _issues(result));
      expect(result.exitCode, 1, reason: _issues(result));
      expect(result.packageRoots, <String>[
        '',
        'deep/arbitrary/package',
        'packages/linked',
        'third_party/override',
      ]);
      expect(result.occurrences.map((entry) => entry.path).toSet(), <String>{
        'lib/new\nline.dart',
        'lib/root.dart',
        'packages/linked/lib/linked.dart',
        'third_party/override/lib/override.dart',
        'deep/arbitrary/package/lib/arbitrary.dart',
      });
      expect(
        result.occurrences.map((entry) => entry.diagnostic).toSet(),
        <String>{'unused_element'},
      );
      expect(
        result.occurrences.map((entry) => entry.targetFingerprint.name).toSet(),
        <String>{
          '_rootSuppressed',
          '_linkedSuppressed',
          '_overrideSuppressed',
          '_arbitrarySuppressed',
          '_newlineSuppressed',
        },
        reason: 'documentation, trailing, package, and newline cases are real',
      );
      expect(
        result.occurrences.every(
          (entry) =>
              entry.directiveKind == SuppressionDirectiveKind.ignore &&
              entry.count == 1 &&
              entry.targetFingerprint.kind == 'function' &&
              entry.targetFingerprint.ownerChain.isEmpty &&
              !entry.targetFingerprint.stableKey.contains('"line"'),
        ),
        isTrue,
      );
      expect(
        _codes(result),
        containsAll(<String>[
          'broad-warning-suppression',
          'file-wide-unused-suppression',
          'unexpected-suppression',
        ]),
      );
      expect(
        result.issues
            .where((entry) => entry.code == 'broad-warning-suppression')
            .length,
        1,
        reason: 'generated type=lint is outside the unused-warning policy',
      );
      expect(
        result.issues
            .where((entry) => entry.code == 'file-wide-unused-suppression')
            .length,
        1,
      );
      expect(
        result.issues.where((entry) => entry.code == 'unexpected-suppression'),
        hasLength(5),
        reason: 'ignored, deleted, string, and prose decoys must be absent',
      );
      expect(
        result.occurrences.map((entry) => entry.path),
        isNot(
          anyOf(contains('lib/ignored.dart'), contains('lib/deleted.dart')),
        ),
      );

      fixture.write('retired/package/pubspec.yaml', 'name: retired_package\n');
      fixture.write(
        'retired/package/lib/still_present.dart',
        'class StillPresent {}\n',
      );
      fixture.stageAll();
      fixture.delete('retired/package/pubspec.yaml');
      final deletedManifest = await fixture.check(_emptyInventory());
      expect(deletedManifest.exitCode, 2, reason: _issues(deletedManifest));
      expect(deletedManifest.trustworthy, isFalse);
      expect(_codes(deletedManifest), contains('untrusted-scan'));

      final safeGitEnvironment = Map<String, String>.of(Platform.environment)
        ..removeWhere(
          (key, _) =>
              const <String>{
                'GIT_DIR',
                'GIT_WORK_TREE',
                'GIT_INDEX_FILE',
                'GIT_COMMON_DIR',
                'GIT_OBJECT_DIRECTORY',
                'GIT_ALTERNATE_OBJECT_DIRECTORIES',
                'GIT_NAMESPACE',
                'GIT_SHALLOW_FILE',
                'GIT_CEILING_DIRECTORIES',
                'GIT_DISCOVERY_ACROSS_FILESYSTEM',
                'GIT_CONFIG_PARAMETERS',
              }.contains(key) ||
              key.startsWith('GIT_CONFIG_'),
        );
      for (final redirected in <String, String>{
        'GIT_DIR': '/tmp/redirected-git-dir',
        'GIT_WORK_TREE': '/tmp/redirected-work-tree',
        'GIT_INDEX_FILE': '/tmp/redirected-index',
        'GIT_COMMON_DIR': '/tmp/redirected-common-dir',
        'GIT_CONFIG_COUNT': '1',
      }.entries) {
        expect(
          () => AnalyzerSuppressionRatchet.listGitVisiblePaths(
            fixture.directory.path,
            environment: <String, String>{
              ...safeGitEnvironment,
              redirected.key: redirected.value,
            },
          ),
          throwsFormatException,
          reason: '${redirected.key} must not redirect repository discovery',
        );
      }
      expect(
        AnalyzerSuppressionRatchet.listGitVisiblePaths(
          fixture.directory.path,
          environment: <String, String>{
            ...safeGitEnvironment,
            'GIT_PAGER': 'cat',
          },
        ).visible,
        contains('pubspec.yaml'),
        reason: 'presentation-only Git variables do not redirect discovery',
      );

      final disappearing = _GitFixture(
        files: <String, String>{
          '.gitignore': '.dart_tool/\n',
          'pubspec.yaml': 'name: disappearing\n',
          'lib/disappearing.dart': 'class Disappearing {}\n',
        },
        packages: const <String, String>{'disappearing': ''},
      );
      addTearDown(disappearing.dispose);
      disappearing.stageAll();
      final vanished = await disappearing.check(
        _emptyInventory(),
        gitPathLister: (repoRoot) {
          final visible = AnalyzerSuppressionRatchet.listGitVisiblePaths(
            repoRoot,
          );
          disappearing.delete('lib/disappearing.dart');
          return visible;
        },
      );
      expect(vanished.exitCode, 2, reason: _issues(vanished));
      expect(vanished.trustworthy, isFalse);
      expect(_codes(vanished), contains('untrusted-scan'));
    },
  );

  test('rejects unexpected relocated duplicate and stale identities', () async {
    final fixture = _GitFixture(
      files: <String, String>{
        '.gitignore': '.dart_tool/\n',
        'pubspec.yaml': 'name: identity_fixture\n',
        'lib/identity.dart': _alphaSuppressedSource,
      },
      packages: const <String, String>{'identity_fixture': ''},
    );
    addTearDown(fixture.dispose);
    fixture.stageAll();

    final discovered = await fixture.check(_emptyInventory());
    expect(discovered.trustworthy, isTrue, reason: _issues(discovered));
    expect(discovered.occurrences, hasLength(1), reason: _issues(discovered));
    final alpha = discovered.occurrences.single;
    expect(alpha.targetFingerprint.kind, 'method');
    expect(alpha.targetFingerprint.ownerChain, <String>['class:Alpha']);
    expect(alpha.targetFingerprint.name, '_same');
    expect(alpha.targetFingerprint.signature, 'void _same ( int value )');

    final exactInventory = _inventoryFrom(<SuppressionOccurrence>[alpha]);
    final exact = await fixture.check(exactInventory);
    expect(exact.exitCode, 0, reason: _issues(exact));

    fixture.write('lib/identity.dart', '\n\n$_alphaSuppressedSource');
    final lineMovedOnly = await fixture.check(exactInventory);
    expect(
      lineMovedOnly.exitCode,
      0,
      reason: 'line numbers are not identity: ${_issues(lineMovedOnly)}',
    );

    final unexpected = await fixture.check(_emptyInventory());
    expect(unexpected.exitCode, 1);
    expect(_codes(unexpected), contains('unexpected-suppression'));

    final relocatedInventory = _inventoryFrom(
      <SuppressionOccurrence>[alpha],
      entryTransform: (entry) => <String, Object?>{
        ...entry,
        'path': 'lib/relocated.dart',
      },
    );
    final relocated = await fixture.check(relocatedInventory);
    expect(relocated.exitCode, 1, reason: _issues(relocated));
    expect(
      _codes(relocated),
      containsAll(<String>['unexpected-suppression', 'stale-inventory-entry']),
    );

    fixture.write('lib/identity.dart', _betaSuppressedSource);
    final targetSwapped = await fixture.check(exactInventory);
    expect(targetSwapped.exitCode, 1, reason: _issues(targetSwapped));
    expect(targetSwapped.occurrences, hasLength(1));
    expect(
      targetSwapped.occurrences.single.targetFingerprint.name,
      alpha.targetFingerprint.name,
    );
    expect(
      targetSwapped.occurrences.single.targetFingerprint.signature,
      alpha.targetFingerprint.signature,
    );
    expect(
      targetSwapped.occurrences.single.targetFingerprint.ownerChain,
      <String>['class:Beta'],
    );
    expect(
      targetSwapped.occurrences.single.identityKey,
      isNot(alpha.identityKey),
    );
    expect(
      _codes(targetSwapped),
      containsAll(<String>['unexpected-suppression', 'stale-inventory-entry']),
    );

    fixture.write('lib/identity.dart', _stringExtensionSuppressedSource);
    final extensionDiscovered = await fixture.check(_emptyInventory());
    expect(
      extensionDiscovered.occurrences,
      hasLength(1),
      reason: _issues(extensionDiscovered),
    );
    final stringExtension = extensionDiscovered.occurrences.single;
    expect(stringExtension.targetFingerprint.kind, 'method');
    expect(stringExtension.targetFingerprint.ownerChain, <String>[
      'extension:<unnamed>:extension on String',
    ]);
    expect(stringExtension.targetFingerprint.name, '_same');
    expect(
      stringExtension.targetFingerprint.signature,
      alpha.targetFingerprint.signature,
    );
    final stringExtensionInventory = _inventoryFrom(<SuppressionOccurrence>[
      stringExtension,
    ]);
    final exactStringExtension = await fixture.check(stringExtensionInventory);
    expect(
      exactStringExtension.exitCode,
      0,
      reason: _issues(exactStringExtension),
    );

    fixture.write('lib/identity.dart', _intExtensionSuppressedSource);
    final extensionTargetSwapped = await fixture.check(
      stringExtensionInventory,
    );
    expect(
      extensionTargetSwapped.exitCode,
      1,
      reason: _issues(extensionTargetSwapped),
    );
    expect(extensionTargetSwapped.occurrences, hasLength(1));
    final intExtension = extensionTargetSwapped.occurrences.single;
    expect(
      intExtension.targetFingerprint.name,
      stringExtension.targetFingerprint.name,
    );
    expect(
      intExtension.targetFingerprint.signature,
      stringExtension.targetFingerprint.signature,
    );
    expect(intExtension.targetFingerprint.ownerChain, <String>[
      'extension:<unnamed>:extension on int',
    ]);
    expect(intExtension.identityKey, isNot(stringExtension.identityKey));
    expect(
      _codes(extensionTargetSwapped),
      containsAll(<String>['unexpected-suppression', 'stale-inventory-entry']),
    );

    fixture.write('lib/identity.dart', '''
class Alpha {
  // ignore: unused_element, unused_element
  void _same(int value) {}
}
''');
    final duplicate = await fixture.check(exactInventory);
    expect(duplicate.exitCode, 1, reason: _issues(duplicate));
    expect(duplicate.occurrences, hasLength(2));
    expect(_codes(duplicate), contains('duplicate-suppression'));

    fixture.write('lib/identity.dart', '''
class Alpha {
  void _same(int value) {}
}
''');
    final stale = await fixture.check(exactInventory);
    expect(stale.exitCode, 1, reason: _issues(stale));
    expect(stale.occurrences, isEmpty);
    expect(_codes(stale), contains('stale-inventory-entry'));
  });

  test('inventory schema is exact reviewed and shrink only', () async {
    final validEntry = <String, Object?>{
      'path': 'lib/example.dart',
      'directiveKind': 'ignore',
      'diagnostic': 'unused_element',
      'targetFingerprint': <String, Object?>{
        'kind': 'function',
        'ownerChain': <String>['class:Owner'],
        'name': '_example',
        'signature': 'void _example ( )',
      },
      'count': 1,
      'sourceKind': 'handwritten',
      'owner': <String, Object?>{'kind': 'roadmap', 'id': 'DTR-TEST'},
      'reason': 'A reviewed fixture suppression.',
      'evidence': <String>['The exact declaration is covered by this test.'],
      'removalCondition': 'Remove with the exact declaration.',
    };
    final valid = _inventoryFromJsonEntries(<Map<String, Object?>>[validEntry]);
    expect(valid.entries, hasLength(1));
    expect(valid.entries.single.targetFingerprint.ownerChain, <String>[
      'class:Owner',
    ]);

    void rejects(
      String label,
      void Function(Map<String, Object?> entry) mutate,
    ) {
      final entry = jsonDecode(jsonEncode(validEntry)) as Map<String, Object?>;
      mutate(entry);
      expect(
        () => _inventoryFromJsonEntries(<Map<String, Object?>>[entry]),
        throwsFormatException,
        reason: label,
      );
    }

    rejects('file-wide entries', (entry) {
      entry['directiveKind'] = 'ignore_for_file';
    });
    rejects('path glob', (entry) {
      entry['path'] = 'lib/**.dart';
    });
    rejects('path wildcard', (entry) {
      entry['path'] = 'lib/example?.dart';
    });
    rejects('path character class', (entry) {
      entry['path'] = 'lib/[ab].dart';
    });
    rejects('path traversal', (entry) {
      entry['path'] = '../lib/example.dart';
    });
    rejects('invalid diagnostic syntax', (entry) {
      entry['diagnostic'] = 'unused_*';
    });
    rejects('non-unused diagnostic', (entry) {
      entry['diagnostic'] = 'avoid_print';
    });
    rejects('zero count', (entry) {
      entry['count'] = 0;
    });
    rejects('larger count', (entry) {
      entry['count'] = 2;
    });
    rejects('numeric lookalike count', (entry) {
      entry['count'] = 1.0;
    });
    rejects('unknown source kind', (entry) {
      entry['sourceKind'] = 'generated-directory';
    });
    rejects('empty owner', (entry) {
      entry['owner'] = <String, Object?>{'kind': 'roadmap', 'id': ''};
    });
    rejects('unknown owner kind', (entry) {
      entry['owner'] = <String, Object?>{'kind': 'team', 'id': 'infra'};
    });
    rejects('generated source must be generator-owned', (entry) {
      entry['sourceKind'] = 'generated';
    });
    rejects('handwritten source must be roadmap-owned', (entry) {
      entry['owner'] = <String, Object?>{
        'kind': 'generator',
        'id': 'fixture.generator',
      };
    });
    rejects('empty reason', (entry) {
      entry['reason'] = '';
    });
    rejects('empty evidence', (entry) {
      entry['evidence'] = <String>[];
    });
    rejects('blank evidence item', (entry) {
      entry['evidence'] = <String>[' '];
    });
    rejects('empty removal condition', (entry) {
      entry['removalCondition'] = '';
    });
    rejects('unknown target kind', (entry) {
      final target = entry['targetFingerprint']! as Map<String, Object?>;
      target['kind'] = 'line';
    });
    rejects('target owner glob', (entry) {
      final target = entry['targetFingerprint']! as Map<String, Object?>;
      target['ownerChain'] = <String>['class:*'];
    });
    rejects('target name wildcard', (entry) {
      final target = entry['targetFingerprint']! as Map<String, Object?>;
      target['name'] = '_example?';
    });
    rejects('target signature glob', (entry) {
      final target = entry['targetFingerprint']! as Map<String, Object?>;
      target['signature'] = 'void _example ( [*] )';
    });
    rejects('line-only identity', (entry) {
      final target = entry['targetFingerprint']! as Map<String, Object?>;
      target['line'] = 17;
    });
    rejects('missing fingerprint field', (entry) {
      final target = entry['targetFingerprint']! as Map<String, Object?>;
      target.remove('signature');
    });
    rejects('unknown entry field', (entry) {
      entry['reviewedAt'] = '2026-07-25';
    });

    final duplicate =
        jsonDecode(jsonEncode(validEntry)) as Map<String, Object?>;
    expect(
      () => _inventoryFromJsonEntries(<Map<String, Object?>>[
        validEntry,
        duplicate,
      ]),
      throwsFormatException,
      reason: 'duplicate identities are not a count budget',
    );
    for (final invalidDocument in <Map<String, Object?>>[
      <String, Object?>{
        'schemaVersion': 2,
        'policy': 'production-unused-suppressions',
        'entries': <Object?>[],
      },
      <String, Object?>{
        'schemaVersion': 1,
        'policy': 'updateable-baseline',
        'entries': <Object?>[],
      },
      <String, Object?>{
        'schemaVersion': 1,
        'policy': 'production-unused-suppressions',
        'entries': <Object?>[],
        'generatedAt': 'now',
      },
    ]) {
      expect(
        () => SuppressionInventory.fromJsonString(jsonEncode(invalidDocument)),
        throwsFormatException,
      );
    }

    for (final arguments in <List<String>>[
      const <String>[],
      const <String>['generate'],
      const <String>['update'],
      const <String>['accept'],
      const <String>['check', '--write'],
    ]) {
      expect(
        await runAnalyzerSuppressionRatchetCli(arguments),
        2,
        reason: 'only one exact read-only check command is supported',
      );
    }
  });

  test(
    'rejects analyzer option ignore and production exclusion bypasses',
    () async {
      final fixture = _GitFixture(
        files: <String, String>{
          '.gitignore': '.dart_tool/\n',
          'pubspec.yaml': 'name: options_root\n',
          'analysis_options.yaml': '{}\n',
          'lib/visible.dart': 'class Visible {}\n',
          'lib/deep/hidden_item.dart': 'class HiddenItem {}\n',
          'nested/pkg/pubspec.yaml': 'name: nested_options\n',
          'nested/pkg/lib/nested.dart': 'class NestedVisible {}\n',
          'config_package/lib/clean.yaml': '''
analyzer:
  errors:
    unused_element: warning
''',
          'config_package/lib/ignore.yaml': '''
analyzer:
  errors:
    unused_element: ignore
''',
        },
        packages: const <String, String>{
          'options_root': '',
          'nested_options': 'nested/pkg',
          'fixture_options': 'config_package',
        },
      );
      addTearDown(fixture.dispose);
      fixture.stageAll();

      Future<SuppressionCheckResult> scan() => fixture.check(_emptyInventory());

      expect((await scan()).exitCode, 0);

      fixture.write('analysis_options.yaml', '''
analyzer:
  errors:
    UnUsEd_FiElD: IGNORE
    UNUSED_ELEMENT: false
''');
      final direct = await scan();
      expect(direct.exitCode, 1, reason: _issues(direct));
      expect(
        direct.issues
            .where(
              (entry) => entry.code == 'unused-diagnostic-globally-ignored',
            )
            .map((entry) => entry.message.toLowerCase()),
        containsAll(<Matcher>[
          contains('unused_field'),
          contains('unused_element'),
        ]),
      );

      fixture.write('config/ignore.yaml', '''
analyzer:
  errors:
    unused_field: ignore
''');
      fixture.write('analysis_options.yaml', 'include: config/ignore.yaml\n');
      final relativeInclude = await scan();
      expect(relativeInclude.exitCode, 1, reason: _issues(relativeInclude));
      expect(
        _codes(relativeInclude),
        contains('unused-diagnostic-globally-ignored'),
      );

      fixture.write(
        'analysis_options.yaml',
        'include: package:fixture_options/ignore.yaml\n',
      );
      final packageInclude = await scan();
      expect(packageInclude.exitCode, 1, reason: _issues(packageInclude));
      expect(
        _codes(packageInclude),
        contains('unused-diagnostic-globally-ignored'),
      );

      fixture.write('config/warning.yaml', '''
analyzer:
  errors:
    unused_field: warning
''');
      fixture.write('analysis_options.yaml', '''
include:
  - config/ignore.yaml
  - config/warning.yaml
''');
      final orderedList = await scan();
      expect(
        orderedList.exitCode,
        0,
        reason:
            'later list include restores warning severity: '
            '${_issues(orderedList)}',
      );

      fixture.write('analysis_options.yaml', '''
include: config/ignore.yaml
analyzer:
  errors:
    unused_field: warning
''');
      final localOverride = await scan();
      expect(
        localOverride.exitCode,
        0,
        reason: 'local override wins include: ${_issues(localOverride)}',
      );

      final contextCacheFixture = _GitFixture(
        files: <String, String>{
          '.gitignore': '**/.dart_tool/\n',
          'pubspec.yaml': 'name: context_cache_root\n',
          'analysis_options.yaml':
              'include: package:fixture_options/clean.yaml\n',
          'lib/root.dart': 'class RootContext {}\n',
          'nested/pkg/pubspec.yaml': 'name: nested_context\n',
          'nested/pkg/lib/nested.dart': 'class NestedContext {}\n',
          'config_package/lib/clean.yaml': '''
analyzer:
  errors:
    unused_element: warning
''',
        },
        packages: const <String, String>{
          'context_cache_root': '',
          'nested_context': 'nested/pkg',
          'fixture_options': 'config_package',
        },
      );
      addTearDown(contextCacheFixture.dispose);
      contextCacheFixture.writePackageConfig(
        'nested/pkg/.dart_tool/package_config.json',
        const <String, String>{'nested_context': 'nested/pkg'},
      );
      contextCacheFixture.stageAll();
      final contextSpecificResolution = await contextCacheFixture.check(
        _emptyInventory(),
      );
      expect(
        contextSpecificResolution.exitCode,
        2,
        reason: _issues(contextSpecificResolution),
      );
      expect(contextSpecificResolution.trustworthy, isFalse);
      expect(_codes(contextSpecificResolution), contains('untrusted-scan'));
      expect(
        _issues(contextSpecificResolution),
        contains('fixture_options'),
        reason:
            'the shared options include must be re-resolved with the nested '
            'session whose package config omits fixture_options',
      );

      fixture.write('analysis_options.yaml', '{}\n');
      fixture.write('nested/pkg/analysis_options.yaml', '''
analyzer:
  errors:
    unused_element: ignore
''');
      final nested = await scan();
      expect(nested.exitCode, 1, reason: _issues(nested));
      expect(
        nested.issues
            .where(
              (entry) => entry.code == 'unused-diagnostic-globally-ignored',
            )
            .map((entry) => entry.path),
        contains('nested/pkg/lib/nested.dart'),
      );

      fixture.write('nested/pkg/analysis_options.yaml', '{}\n');
      fixture.write('analysis_options.yaml', '''
analyzer:
  exclude:
    - "lib/**/hidden_*.dart"
''');
      final exclusion = await scan();
      expect(exclusion.exitCode, 1, reason: _issues(exclusion));
      expect(
        exclusion.issues
            .where((entry) => entry.code == 'production-source-excluded')
            .map((entry) => entry.path),
        contains('lib/deep/hidden_item.dart'),
      );

      fixture.write('analysis_options.yaml', '''
analyzer:
  errors:
    avoid_print: ignore
''');
      fixture.write('test/integration_decoy.dart', '''
// ignore: unused_element
void _testOnlySuppression() {}
''');
      final unrelated = await scan();
      expect(
        unrelated.exitCode,
        0,
        reason: 'non-unused options and test sources are out of scope',
      );
      expect(unrelated.occurrences, isEmpty);

      final nearestNestedInvalidCases = <String, Map<String, String>>{
        'nearest missing include': <String, String>{
          'lib/deep/analysis_options.yaml': 'include: missing.yaml\n',
        },
        'nearest malformed config': <String, String>{
          'lib/deep/analysis_options.yaml': 'analyzer: []\n',
        },
        'nearest cyclic includes': <String, String>{
          'lib/deep/analysis_options.yaml': 'include: cycle.yaml\n',
          'lib/deep/cycle.yaml': 'include: analysis_options.yaml\n',
        },
      };
      for (final invalid in nearestNestedInvalidCases.entries) {
        fixture.writeAll(invalid.value);
        final result = await scan();
        expect(
          result.exitCode,
          2,
          reason: '${invalid.key}: ${_issues(result)}',
        );
        expect(
          result.trustworthy,
          isFalse,
          reason: '${invalid.key}: ${_issues(result)}',
        );
        expect(_codes(result), contains('untrusted-scan'), reason: invalid.key);
        if (invalid.key == 'nearest missing include') {
          expect(
            _issues(result),
            contains('missing.yaml'),
            reason: 'the config beside lib/deep/hidden_item.dart must apply',
          );
        }
      }
      fixture.write('lib/deep/analysis_options.yaml', '{}\n');

      final invalidCases = <String, Map<String, String>>{
        'missing include': <String, String>{
          'analysis_options.yaml': 'include: config/missing.yaml\n',
        },
        'malformed include shape': <String, String>{
          'analysis_options.yaml': 'include: {path: config/ignore.yaml}\n',
        },
        'malformed analyzer section': <String, String>{
          'analysis_options.yaml': 'analyzer: []\n',
        },
        'malformed errors section': <String, String>{
          'analysis_options.yaml': 'analyzer:\n  errors: []\n',
        },
        'malformed exclude section': <String, String>{
          'analysis_options.yaml': 'analyzer:\n  exclude: lib/**\n',
        },
        'unresolved package include': <String, String>{
          'analysis_options.yaml': 'include: package:absent/options.yaml\n',
        },
        'cyclic includes': <String, String>{
          'analysis_options.yaml': 'include: config/cycle_a.yaml\n',
          'config/cycle_a.yaml': 'include: cycle_b.yaml\n',
          'config/cycle_b.yaml': 'include: cycle_a.yaml\n',
        },
      };
      for (final invalid in invalidCases.entries) {
        fixture.write('nested/pkg/analysis_options.yaml', '{}\n');
        fixture.writeAll(invalid.value);
        final result = await scan();
        expect(
          result.exitCode,
          2,
          reason: '${invalid.key}: ${_issues(result)}',
        );
        expect(
          result.trustworthy,
          isFalse,
          reason: '${invalid.key}: ${_issues(result)}',
        );
        expect(_codes(result), contains('untrusted-scan'), reason: invalid.key);
      }
    },
  );

  test(
    'canonical repository inventory is the three generated l10n identities plus the DTR-05 relay helper',
    () async {
      final repoRoot = Directory.current.absolute.path;
      final inventoryFile = File(
        '$repoRoot/tool/analyzer_guard/production_unused_suppressions.json',
      );
      final inventory = SuppressionInventory.loadSync(inventoryFile);
      final result = await AnalyzerSuppressionRatchet(
        repoRoot: repoRoot,
        inventory: inventory,
      ).check();

      expect(result.exitCode, 0, reason: _issues(result));
      expect(result.trustworthy, isTrue, reason: _issues(result));
      expect(result.hasPolicyDrift, isFalse, reason: _issues(result));
      expect(result.packageRoots, <String>[
        '',
        'packages/background_push_crypto',
        'third_party/bonsoir_darwin',
      ]);
      expect(inventory.entries, hasLength(4));
      expect(result.occurrences, hasLength(4));
      expect(
        result.occurrences.map((entry) => entry.identityKey).toSet(),
        inventory.entries.map((entry) => entry.identityKey).toSet(),
      );
      expect(inventory.entries.map((entry) => entry.path).toSet(), <String>{
        'lib/l10n/app_localizations_ar.dart',
        'lib/l10n/app_localizations_de.dart',
        'lib/l10n/app_localizations_en.dart',
        'lib/features/conversation/application/'
            'send_chat_message_use_case.dart',
      });
      expect(
        inventory.entries
            .where((entry) => entry.sourceKind == 'generated')
            .map((entry) => '${entry.ownerKind}:${entry.ownerId}')
            .toSet(),
        <String>{'generator:flutter.gen-l10n'},
      );
      expect(
        inventory.entries
            .where((entry) => entry.sourceKind == 'generated')
            .length,
        3,
      );
      final handwritten = inventory.entries.singleWhere(
        (entry) => entry.sourceKind == 'handwritten',
      );
      expect(
        '${handwritten.ownerKind}:${handwritten.ownerId}',
        'roadmap:DTR-05',
      );
      expect(handwritten.diagnostic, 'unused_element');
      expect(handwritten.targetFingerprint.kind, 'function');
      expect(handwritten.targetFingerprint.ownerChain, isEmpty);
      expect(handwritten.targetFingerprint.name, '_tryRelayProbeSend');
      expect(
        handwritten.targetFingerprint.signature,
        'Future < _RaceResult > _tryRelayProbeSend ( P2PService p2pService , '
        'String targetPeerId , String jsonString , { required String '
        'failureReason , required String messageId , } )',
      );
      for (final entry in inventory.entries.where(
        (entry) => entry.sourceKind == 'generated',
      )) {
        expect(entry.diagnostic, 'unused_import');
        expect(entry.targetFingerprint.kind, 'import');
        expect(entry.targetFingerprint.ownerChain, isEmpty);
        expect(entry.targetFingerprint.name, 'package:intl/intl.dart');
        expect(
          entry.targetFingerprint.signature,
          'uri=package:intl/intl.dart;prefix=intl;deferred=false;'
          'combinators=[]',
        );
      }

      final pubspec =
          loadYaml(File('$repoRoot/pubspec.yaml').readAsStringSync())
              as YamlMap;
      expect((pubspec['flutter'] as YamlMap)['generate'], isTrue);
    },
  );
}

const String _alphaSuppressedSource = '''
class Alpha {
  // ignore: unused_element
  void _same(int value) {}
}

class Beta {
  void _same(int value) {}
}
''';

const String _betaSuppressedSource = '''
class Alpha {
  void _same(int value) {}
}

class Beta {
  // ignore: unused_element
  void _same(int value) {}
}
''';

const String _stringExtensionSuppressedSource = '''
extension on String {
  // ignore: unused_element
  void _same(int value) {}
}

extension on int {
  void _same(int value) {}
}
''';

const String _intExtensionSuppressedSource = '''
extension on String {
  void _same(int value) {}
}

extension on int {
  // ignore: unused_element
  void _same(int value) {}
}
''';

class _GitFixture {
  _GitFixture({
    required Map<String, String> files,
    required Map<String, String> packages,
  }) : directory = Directory.systemTemp.createTempSync(
         'analyzer suppression ratchet fixture ',
       ) {
    writeAll(files);
    writePackageConfig('.dart_tool/package_config.json', packages);
    _runGit(<String>['init', '--quiet']);
  }

  final Directory directory;

  void writeAll(Map<String, String> files) {
    for (final entry in files.entries) {
      write(entry.key, entry.value);
    }
  }

  void write(String path, String contents) {
    final file = File(_path(path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  void delete(String path) {
    final entity = File(_path(path));
    if (entity.existsSync()) entity.deleteSync();
  }

  void stageAll() {
    _runGit(<String>['add', '--all', '--', '.']);
  }

  void writePackageConfig(String configPath, Map<String, String> packages) {
    final entries = <Map<String, Object?>>[];
    for (final entry in packages.entries) {
      final root = Directory(
        entry.value.isEmpty ? directory.path : _path(entry.value),
      );
      entries.add(<String, Object?>{
        'name': entry.key,
        'rootUri': root.uri.toString(),
        'packageUri': 'lib/',
        'languageVersion': '3.9',
      });
    }
    write(
      configPath,
      jsonEncode(<String, Object?>{'configVersion': 2, 'packages': entries}),
    );
  }

  Future<SuppressionCheckResult> check(
    SuppressionInventory inventory, {
    GitPathLister? gitPathLister,
  }) => AnalyzerSuppressionRatchet(
    repoRoot: directory.path,
    inventory: inventory,
    gitPathLister: gitPathLister,
  ).check();

  void dispose() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }

  void _runGit(List<String> arguments) {
    final result = Process.runSync(
      'git',
      arguments,
      workingDirectory: directory.path,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      throw StateError(
        'git ${arguments.join(' ')} failed (${result.exitCode}): '
        '${result.stderr}',
      );
    }
  }

  String _path(String relativePath) {
    final segments = relativePath.split('/');
    return <String>[directory.path, ...segments].join(Platform.pathSeparator);
  }
}

SuppressionInventory _emptyInventory() =>
    _inventoryFromJsonEntries(const <Map<String, Object?>>[]);

SuppressionInventory _inventoryFrom(
  Iterable<SuppressionOccurrence> occurrences, {
  Map<String, Object?> Function(Map<String, Object?> entry)? entryTransform,
}) {
  final entries = occurrences.map((occurrence) {
    final entry = <String, Object?>{
      'path': occurrence.path,
      'directiveKind': occurrence.directiveKind.wireName,
      'diagnostic': occurrence.diagnostic,
      'targetFingerprint': occurrence.targetFingerprint.toJson(),
      'count': occurrence.count,
      'sourceKind': 'handwritten',
      'owner': <String, Object?>{'kind': 'roadmap', 'id': 'DTR-TEST'},
      'reason': 'The fixture retains this exact declaration.',
      'evidence': <String>['The named unit test proves the exact identity.'],
      'removalCondition': 'Remove with the exact fixture declaration.',
    };
    return entryTransform == null ? entry : entryTransform(entry);
  }).toList();
  return _inventoryFromJsonEntries(entries);
}

SuppressionInventory _inventoryFromJsonEntries(
  List<Map<String, Object?>> entries,
) => SuppressionInventory.fromJsonString(
  jsonEncode(<String, Object?>{
    'schemaVersion': 1,
    'policy': 'production-unused-suppressions',
    'entries': entries,
  }),
);

Set<String> _codes(SuppressionCheckResult result) =>
    result.issues.map((entry) => entry.code).toSet();

String _issues(SuppressionCheckResult result) =>
    result.issues.map((entry) => entry.toString()).join('\n');
