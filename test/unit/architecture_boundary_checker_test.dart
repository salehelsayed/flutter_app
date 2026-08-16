import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/architecture_guard/architecture_boundary_checker.dart';

void main() {
  test('discovers and normalizes package relative export part and conditional '
      'dependencies without lexical decoys', () {
    final analysis = ArchitectureBoundaryChecker.analyzeSourcesForTesting(
      packageName: 'fixture_app',
      sources: const <String, String>{
        'lib/core/services/entry.dart': '''
library fixture.library;

import 'package:fixture_app/features/chat/domain/package_target.dart';
import '../../features/chat/domain/package_target.dart';
export '../../features/chat/application/export_target.dart';
import 'fallback.dart'
  if (dart.library.io) '../../features/chat/domain/io_target.dart'
  if (dart.library.html) '../../features/chat/presentation/web_target.dart';
export 'local_export.dart'
  if (dart.library.io) '../../features/chat/application/conditional_export.dart';
import 'dart:async';
import 'package:external_package/external.dart';
part '../../features/chat/domain/piece.dart';
part 'named_piece.dart';

const lexicalDecoy =
    "import '../../features/chat/domain/not_a_dependency.dart';";
// export '../../features/chat/domain/also_not_a_dependency.dart';
''',
        'lib/core/services/fallback.dart': '',
        'lib/core/services/local_export.dart': '',
        'lib/core/services/named_piece.dart': 'part of fixture.library;',
        'lib/features/chat/domain/package_target.dart': '',
        'lib/features/chat/application/export_target.dart': '',
        'lib/features/chat/application/conditional_export.dart': '',
        'lib/features/chat/domain/io_target.dart': '',
        'lib/features/chat/presentation/web_target.dart': '',
        'lib/features/chat/domain/piece.dart': '''
part of '../../../core/services/entry.dart';
''',
      },
    );

    expect(analysis.fatalIssues, isEmpty);
    expect(
      analysis.dependencies
          .map((dependency) => dependency.normalizedIdentity)
          .toList(),
      unorderedEquals(<String>[
        'lib/core/services/entry.dart|import|'
            'lib/features/chat/domain/package_target.dart',
        'lib/core/services/entry.dart|import|'
            'lib/features/chat/domain/package_target.dart',
        'lib/core/services/entry.dart|export|'
            'lib/features/chat/application/export_target.dart',
        'lib/core/services/entry.dart|import|'
            'lib/core/services/fallback.dart',
        'lib/core/services/entry.dart|conditional-import|'
            'lib/features/chat/domain/io_target.dart',
        'lib/core/services/entry.dart|conditional-import|'
            'lib/features/chat/presentation/web_target.dart',
        'lib/core/services/entry.dart|export|'
            'lib/core/services/local_export.dart',
        'lib/core/services/entry.dart|conditional-export|'
            'lib/features/chat/application/conditional_export.dart',
        'lib/core/services/entry.dart|part|'
            'lib/features/chat/domain/piece.dart',
        'lib/core/services/entry.dart|part|'
            'lib/core/services/named_piece.dart',
        'lib/core/services/named_piece.dart|part-of|'
            'lib/core/services/entry.dart',
        'lib/features/chat/domain/piece.dart|part-of|'
            'lib/core/services/entry.dart',
      ]),
    );
    expect(
      analysis.dependencies
          .map((dependency) => dependency.targetPath)
          .where((path) => path.contains('not_a_dependency')),
      isEmpty,
    );
    final mismatchedNamedPart =
        ArchitectureBoundaryChecker.analyzeSourcesForTesting(
          packageName: 'fixture_app',
          sources: const <String, String>{
            'lib/core/owner.dart': '''
library correct.name;
part 'piece.dart';
''',
            'lib/core/piece.dart': 'part of wrong.name;',
          },
        );
    expect(
      mismatchedNamedPart.fatalIssues,
      contains(contains('does not declare that exact library name')),
    );
  });

  test(
    'canonical DTR-12 manifest pins 169 dependency and zero placement exceptions',
    () {
      final root = _findRepositoryRoot();
      final manifest = ArchitectureBoundaryManifest.loadSync(
        File(
          p.join(
            root,
            'tool',
            'architecture_guard',
            'architecture_boundary_exceptions.json',
          ),
        ),
      );
      final result = ArchitectureBoundaryChecker(
        repoRoot: root,
        manifest: manifest,
      ).check();

      expect(manifest.dependencyExceptions, hasLength(169));
      expect(manifest.placementExceptions, isEmpty);
      expect(
        manifest.dependencyExceptions.where(
          (entry) => entry.source.startsWith('lib/core/debug/'),
        ),
        hasLength(96),
      );
      expect(result.trustworthy, isTrue, reason: _issues(result));
      expect(result.hasPolicyDrift, isFalse, reason: _issues(result));
      expect(result.dependencyViolations, hasLength(169));
      expect(result.placementViolations, isEmpty);
      expect(
        result.dependencyViolations.where(
          (dependency) =>
              dependency.sourcePath.startsWith('lib/core/') &&
              dependency.literalUri.startsWith('package:'),
        ),
        hasLength(141),
      );
      expect(
        result.dependencyViolations.where(
          (dependency) =>
              dependency.sourcePath.startsWith('lib/core/') &&
              !dependency.literalUri.startsWith('package:'),
        ),
        hasLength(20),
      );
      expect(result.exitCodeFor(check: true), 0);
    },
  );

  test('enforces the documented four-layer direction and shared-widget '
      'presentation alias', () {
    const sources = <String, String>{
      'lib/core/source.dart': '''
import 'package:fixture/features/alpha/domain/domain.dart';
import 'package:fixture/features/alpha/misc/misc.dart';
import 'package:fixture/shared/widgets/shared_widget.dart';
import 'package:fixture/core/peer.dart';
''',
      'lib/core/peer.dart': '',
      'lib/features/alpha/domain/domain.dart': '''
import 'package:fixture/features/alpha/application/application.dart';
import 'package:fixture/features/alpha/presentation/presentation.dart';
import 'package:fixture/shared/widgets/shared_widget.dart';
import 'package:fixture/core/peer.dart';
import 'package:fixture/features/beta/domain/domain.dart';
''',
      'lib/features/beta/domain/domain.dart': '',
      'lib/features/alpha/application/application.dart': '''
import 'package:fixture/features/alpha/presentation/presentation.dart';
import 'package:fixture/shared/widgets/shared_widget.dart';
import 'package:fixture/features/alpha/domain/domain.dart';
import 'package:fixture/features/beta/application/application.dart';
''',
      'lib/features/beta/application/application.dart': '',
      'lib/features/alpha/presentation/presentation.dart': '''
import 'package:fixture/features/alpha/application/application.dart';
import 'package:fixture/features/alpha/domain/domain.dart';
''',
      'lib/features/alpha/misc/misc.dart': '',
      'lib/shared/widgets/shared_widget.dart': '',
    };

    final analysis = ArchitectureBoundaryChecker.analyzeSourcesForTesting(
      packageName: 'fixture',
      sources: sources,
    );
    expect(analysis.fatalIssues, isEmpty);
    expect(
      analysis.dependencyViolations
          .map(
            (dependency) =>
                '${dependency.violationRule}|${dependency.sourcePath}|'
                '${dependency.targetPath}',
          )
          .toSet(),
      equals(<String>{
        '$coreFeatureDependencyRule|lib/core/source.dart|'
            'lib/features/alpha/domain/domain.dart',
        '$coreFeatureDependencyRule|lib/core/source.dart|'
            'lib/features/alpha/misc/misc.dart',
        '$upwardLayerDependencyRule|lib/core/source.dart|'
            'lib/shared/widgets/shared_widget.dart',
        '$upwardLayerDependencyRule|lib/features/alpha/domain/domain.dart|'
            'lib/features/alpha/application/application.dart',
        '$upwardLayerDependencyRule|lib/features/alpha/domain/domain.dart|'
            'lib/features/alpha/presentation/presentation.dart',
        '$upwardLayerDependencyRule|lib/features/alpha/domain/domain.dart|'
            'lib/shared/widgets/shared_widget.dart',
        '$upwardLayerDependencyRule|'
            'lib/features/alpha/application/application.dart|'
            'lib/features/alpha/presentation/presentation.dart',
        '$upwardLayerDependencyRule|'
            'lib/features/alpha/application/application.dart|'
            'lib/shared/widgets/shared_widget.dart',
      }),
    );
    expect(
      architectureLayerForPath('lib/shared/widgets/shared_widget.dart'),
      ArchitectureLayer.presentation,
    );
    expect(
      analysis.dependencies.where(
        (dependency) =>
            dependency.sourcePath.contains('/presentation/') &&
            dependency.violationRule != null,
      ),
      isEmpty,
    );
  });

  test('pins concrete domain repository implementations semantically without '
      'widening relocation policy', () {
    final analysis = ArchitectureBoundaryChecker.analyzeSourcesForTesting(
      packageName: 'fixture',
      sources: const <String, String>{
        'lib/features/chat/domain/by_name_repository_impl.dart':
            'class HarmlessName {}',
        'lib/features/chat/domain/renamed_adapter.dart':
            'class ChatRepositoryImpl {}',
        'lib/features/chat/domain/implements_adapter.dart':
            'class Adapter implements ChatRepository {}',
        'lib/features/chat/domain/extends_adapter.dart':
            'class Adapter extends ChatRepository {}',
        'lib/features/chat/domain/class_alias_adapter.dart': '''
class Base {}
mixin Behavior {}
class AliasAdapter = Base with Behavior implements ChatRepository;
''',
        'lib/features/chat/domain/typedef_adapter.dart': '''
typedef Contract = ChatRepository;
class TypedefAdapter implements Contract {}
''',
        'lib/features/chat/domain/inherited_adapter.dart': '''
abstract class RepositoryBase implements ChatRepository {}
class InheritedAdapter extends RepositoryBase {}
''',
        'lib/features/chat/domain/chat_repository.dart':
            'abstract interface class ChatRepository {}',
        'lib/features/chat/domain/abstract_adapter.dart':
            'abstract class Adapter implements ChatRepository {}',
        'lib/features/chat/domain/sealed_adapter.dart':
            'sealed class Adapter implements ChatRepository {}',
        'lib/features/chat/application/application_repository_impl.dart':
            'class ApplicationRepositoryImpl {}',
        'lib/features/chat/infrastructure/chat_repository_impl.dart':
            'class ChatRepositoryImpl implements ChatRepository {}',
      },
    );

    expect(analysis.fatalIssues, isEmpty);
    expect(
      analysis.placementViolations.map((entry) => entry.path).toSet(),
      equals(<String>{
        'lib/features/chat/domain/by_name_repository_impl.dart',
        'lib/features/chat/domain/renamed_adapter.dart',
        'lib/features/chat/domain/implements_adapter.dart',
        'lib/features/chat/domain/extends_adapter.dart',
        'lib/features/chat/domain/class_alias_adapter.dart',
        'lib/features/chat/domain/typedef_adapter.dart',
        'lib/features/chat/domain/inherited_adapter.dart',
      }),
    );
    expect(
      analysis.placementViolations
          .where(
            (entry) =>
                entry.path ==
                'lib/features/chat/domain/by_name_repository_impl.dart',
          )
          .single
          .trigger,
      'filename-suffix',
    );
  });

  test('rejects unknown duplicate wildcard ownerless stale and target-swapped '
      'exception rows', () {
    final fixture = _SourceFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeAll(<String, String>{
      'pubspec.yaml': 'name: fixture\n',
      'lib/core/source.dart': '''
import 'package:fixture/features/chat/domain/a.dart';
''',
      'lib/features/chat/domain/a.dart': '',
      'lib/features/chat/domain/b.dart': '',
    });
    final exactRow = _dependencyRow(
      source: 'lib/core/source.dart',
      target: 'lib/features/chat/domain/a.dart',
    );
    final exactManifest = _manifest(dependencies: <Object?>[exactRow]);
    final exactResult = fixture.check(exactManifest);
    expect(exactResult.exact, isTrue, reason: _issues(exactResult));

    fixture.write('lib/core/source.dart', '''


import '../features/chat/domain/a.dart';
''');
    final lineAndSpellingMoved = fixture.check(exactManifest);
    expect(
      lineAndSpellingMoved.exact,
      isTrue,
      reason: _issues(lineAndSpellingMoved),
    );

    final swappedManifest = _manifest(
      dependencies: <Object?>[
        _dependencyRow(
          source: 'lib/core/source.dart',
          target: 'lib/features/chat/domain/b.dart',
        ),
      ],
    );
    final swapped = fixture.check(swappedManifest);
    expect(
      swapped.issues.map((issue) => issue.code).toSet(),
      containsAll(<String>{'new-dependency', 'stale-dependency-exception'}),
    );

    fixture.write('lib/core/source.dart', '');
    final stale = fixture.check(exactManifest);
    expect(
      stale.issues.map((issue) => issue.code),
      contains('stale-dependency-exception'),
    );

    fixture.write('lib/core/source.dart', '''
import 'package:fixture/features/chat/domain/a.dart';
import '../features/chat/domain/a.dart';
''');
    final duplicateActual = fixture.check(exactManifest);
    expect(
      duplicateActual.issues.map((issue) => issue.code),
      contains('duplicate-dependency'),
    );

    final unknownTop = _manifestJson()..['unknown'] = true;
    expect(
      () => ArchitectureBoundaryManifest.fromJsonString(jsonEncode(unknownTop)),
      throwsA(isA<FormatException>()),
    );
    final unknownRow = Map<String, Object?>.from(exactRow)..['unknown'] = true;
    expect(
      () => _manifest(dependencies: <Object?>[unknownRow]),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => _manifest(dependencies: <Object?>[exactRow, exactRow]),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => _manifest(
        dependencies: <Object?>[
          <String, Object?>{...exactRow, 'source': 'lib/core/*.dart'},
        ],
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => _manifest(
        dependencies: <Object?>[
          <String, Object?>{...exactRow, 'owner': ''},
        ],
      ),
      throwsA(isA<FormatException>()),
    );
    final validEmptyJson = jsonEncode(_manifestJson());
    expect(
      () => ArchitectureBoundaryManifest.fromJsonString(
        validEmptyJson.replaceFirst(
          '"schemaVersion":1',
          '"schemaVersion":1,"schemaVersion":1',
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    final validRowJson = jsonEncode(
      _manifestJson(dependencies: <Object?>[exactRow]),
    );
    expect(
      () => ArchitectureBoundaryManifest.fromJsonString(
        validRowJson.replaceFirst(
          '"owner":"DTR-18"',
          '"owner":"DTR-18","owner":"DTR-18"',
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('git-visible discovery rejects redirected or escaping state and is byte '
      'deterministic', () {
    final fixture = _GitFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeAll(<String, String>{
      'pubspec.yaml': 'name: git_fixture\n',
      '.gitignore': 'lib/core/ignored.dart\n',
      'lib/core/stable.dart': 'class Stable {}',
      'lib/core/deleted.dart': 'class Deleted {}',
    });
    fixture.git(<String>['add', '--', '.']);
    fixture.git(<String>[
      '-c',
      'user.name=Architecture Guard',
      '-c',
      'user.email=guard@example.invalid',
      'commit',
      '-qm',
      'fixture',
    ]);
    fixture.write('lib/core/untracked space.dart', 'class Untracked {}');
    fixture.write('lib/core/new\nline.dart', 'class Newline {}');
    fixture.write('lib/core/ignored.dart', 'class Ignored {}');
    fixture.delete('lib/core/deleted.dart');

    final paths = ArchitectureBoundaryChecker.listGitVisiblePaths(
      fixture.root.path,
    );
    expect(paths.visible, contains('lib/core/untracked space.dart'));
    expect(paths.visible, contains('lib/core/new\nline.dart'));
    expect(paths.visible, isNot(contains('lib/core/ignored.dart')));
    expect(paths.deleted, contains('lib/core/deleted.dart'));

    final checker = ArchitectureBoundaryChecker(
      repoRoot: fixture.root.path,
      manifest: ArchitectureBoundaryManifest.fromJsonString(
        jsonEncode(_manifestJson()),
      ),
    );
    final first = checker.check();
    final second = checker.check();
    expect(first.trustworthy, isTrue, reason: _issues(first));
    expect(first.scannedPaths, contains('lib/core/untracked space.dart'));
    expect(first.scannedPaths, contains('lib/core/new\nline.dart'));
    expect(first.scannedPaths, isNot(contains('lib/core/deleted.dart')));
    expect(first.toJsonText(), second.toJsonText());

    expect(
      () => ArchitectureBoundaryChecker.listGitVisiblePaths(
        fixture.root.path,
        environment: <String, String>{
          ...Platform.environment,
          'GIT_INDEX_FILE': p.join(fixture.root.path, 'redirected-index'),
        },
      ),
      throwsA(isA<FormatException>()),
    );

    final outside = Directory.systemTemp.createTempSync(
      'architecture-guard-outside-',
    );
    addTearDown(() => outside.deleteSync(recursive: true));
    final outsideFile = File(p.join(outside.path, 'escape.dart'))
      ..writeAsStringSync('class Escape {}');
    Link(
      p.join(fixture.root.path, 'lib', 'core', 'escape.dart'),
    ).createSync(outsideFile.path);
    final escaping = checker.check();
    expect(escaping.trustworthy, isFalse);
    expect(escaping.exitCodeFor(check: false), 2);

    final injectedEscape = ArchitectureBoundaryChecker(
      repoRoot: fixture.root.path,
      manifest: ArchitectureBoundaryManifest.fromJsonString(
        jsonEncode(_manifestJson()),
      ),
      gitPathLister: (_) => const GitVisiblePaths(
        visible: <String>['pubspec.yaml', '../escape.dart'],
        deleted: <String>[],
      ),
    ).check();
    expect(injectedEscape.trustworthy, isFalse);
  });
}

String _findRepositoryRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final pubspec = File(p.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains(
          RegExp(r'^name: flutter_app$', multiLine: true),
        )) {
      return current.resolveSymbolicLinksSync();
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Could not locate the flutter_app repository root.');
    }
    current = parent;
  }
}

String _issues(ArchitectureBoundaryResult result) =>
    result.issues.map((issue) => issue.toString()).join('\n');

Map<String, Object?> _manifestJson({
  List<Object?> dependencies = const <Object?>[],
  List<Object?> placements = const <Object?>[],
}) => <String, Object?>{
  'schemaVersion': 1,
  'policy': <String, Object?>{
    'layers': architecturePolicyLayers,
    'rules': architecturePolicyRules,
  },
  'dependencyExceptions': dependencies,
  'placementExceptions': placements,
};

ArchitectureBoundaryManifest _manifest({
  List<Object?> dependencies = const <Object?>[],
  List<Object?> placements = const <Object?>[],
}) => ArchitectureBoundaryManifest.fromJsonString(
  jsonEncode(_manifestJson(dependencies: dependencies, placements: placements)),
);

Map<String, Object?> _dependencyRow({
  required String source,
  required String target,
  ArchitectureDirectiveKind directiveKind = ArchitectureDirectiveKind.import,
}) => <String, Object?>{
  'rule': architectureDependencyRule(source, target),
  'sourceLayer': architectureLayerForPath(source).wireName,
  'targetLayer': architectureLayerForPath(target).wireName,
  'source': source,
  'directiveKind': directiveKind.wireName,
  'target': target,
  'count': 1,
  'owner': 'DTR-18',
  'reason': 'Reviewed fixture debt.',
  'evidence': 'Focused DTR-12 test fixture.',
  'condition': 'Remove this exact dependency; never substitute an exception.',
};

class _SourceFixture {
  _SourceFixture._(this.root);

  factory _SourceFixture.create() =>
      _SourceFixture._(Directory.systemTemp.createTempSync('dtr12-source-'));

  final Directory root;
  final Set<String> _paths = <String>{};

  void writeAll(Map<String, String> files) => files.forEach(write);

  void write(String relativePath, String content) {
    final file = File(
      p.joinAll(<String>[root.path, ...p.posix.split(relativePath)]),
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    _paths.add(relativePath);
  }

  ArchitectureBoundaryResult check(ArchitectureBoundaryManifest manifest) =>
      ArchitectureBoundaryChecker(
        repoRoot: root.path,
        manifest: manifest,
        gitPathLister: (_) => GitVisiblePaths(
          visible: _paths.toList(),
          deleted: const <String>[],
        ),
      ).check();

  void dispose() => root.deleteSync(recursive: true);
}

class _GitFixture {
  _GitFixture._(this.root);

  factory _GitFixture.create() {
    final fixture = _GitFixture._(
      Directory.systemTemp.createTempSync('dtr12-git-'),
    );
    fixture.git(const <String>['init', '-q']);
    return fixture;
  }

  final Directory root;

  void writeAll(Map<String, String> files) => files.forEach(write);

  void write(String relativePath, String content) {
    final file = File(
      p.joinAll(<String>[root.path, ...p.posix.split(relativePath)]),
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  void delete(String relativePath) {
    File(
      p.joinAll(<String>[root.path, ...p.posix.split(relativePath)]),
    ).deleteSync();
  }

  void git(List<String> arguments) {
    final result = Process.runSync(
      'git',
      <String>['-C', root.path, ...arguments],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
    }
  }

  void dispose() => root.deleteSync(recursive: true);
}
