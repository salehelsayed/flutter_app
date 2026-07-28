import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

const String coreFeatureDependencyRule = 'core-must-not-depend-on-feature';
const String upwardLayerDependencyRule = 'lower-layer-must-not-depend-upward';
const String domainRepositoryPlacementRule =
    'feature-domain-concrete-repository';

const List<String> architecturePolicyLayers = <String>[
  'core',
  'domain',
  'application',
  'presentation',
];

const List<String> architecturePolicyRules = <String>[
  coreFeatureDependencyRule,
  upwardLayerDependencyRule,
  domainRepositoryPlacementRule,
];

enum ArchitectureLayer {
  core('core', 0),
  domain('domain', 1),
  application('application', 2),
  presentation('presentation', 3),
  unclassified('unclassified', -1);

  const ArchitectureLayer(this.wireName, this.rank);

  final String wireName;
  final int rank;

  static ArchitectureLayer parse(String value) => values.firstWhere(
    (layer) => layer.wireName == value,
    orElse: () => throw FormatException('Unknown architecture layer: $value'),
  );
}

enum ArchitectureDirectiveKind {
  import('import'),
  conditionalImport('conditional-import'),
  export('export'),
  conditionalExport('conditional-export'),
  part('part'),
  partOf('part-of');

  const ArchitectureDirectiveKind(this.wireName);

  final String wireName;

  static ArchitectureDirectiveKind parse(String value) => values.firstWhere(
    (kind) => kind.wireName == value,
    orElse: () => throw FormatException('Unknown directive kind: $value'),
  );
}

enum ArchitectureIssueKind { policy, untrusted }

class ArchitectureIssue implements Comparable<ArchitectureIssue> {
  const ArchitectureIssue({
    required this.kind,
    required this.code,
    required this.message,
    this.path,
    this.line,
  });

  final ArchitectureIssueKind kind;
  final String code;
  final String message;
  final String? path;
  final int? line;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'code': code,
    'message': message,
    if (path != null) 'path': path,
    if (line != null) 'line': line,
  };

  @override
  int compareTo(ArchitectureIssue other) {
    final kindOrder = kind.index.compareTo(other.kind.index);
    if (kindOrder != 0) return kindOrder;
    final pathOrder = (path ?? '').compareTo(other.path ?? '');
    if (pathOrder != 0) return pathOrder;
    final lineOrder = (line ?? 0).compareTo(other.line ?? 0);
    if (lineOrder != 0) return lineOrder;
    final codeOrder = code.compareTo(other.code);
    if (codeOrder != 0) return codeOrder;
    return message.compareTo(other.message);
  }

  @override
  String toString() {
    final location = path == null
        ? ''
        : line == null
        ? '$path: '
        : '$path:$line: ';
    return '$location$code: $message';
  }
}

class ResolvedArchitectureDependency
    implements Comparable<ResolvedArchitectureDependency> {
  const ResolvedArchitectureDependency({
    required this.sourcePath,
    required this.targetPath,
    required this.directiveKind,
    required this.literalUri,
    required this.line,
  });

  final String sourcePath;
  final String targetPath;
  final ArchitectureDirectiveKind directiveKind;
  final String literalUri;
  final int line;

  ArchitectureLayer get sourceLayer => architectureLayerForPath(sourcePath);
  ArchitectureLayer get targetLayer => architectureLayerForPath(targetPath);
  String? get violationRule =>
      architectureDependencyRule(sourcePath, targetPath);

  String get normalizedIdentity =>
      '$sourcePath|${directiveKind.wireName}|$targetPath';

  String get violationIdentity => jsonEncode(<String, Object?>{
    'rule': violationRule,
    'source': sourcePath,
    'directiveKind': directiveKind.wireName,
    'target': targetPath,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    if (violationRule != null) 'rule': violationRule,
    'sourceLayer': sourceLayer.wireName,
    'targetLayer': targetLayer.wireName,
    'source': sourcePath,
    'directiveKind': directiveKind.wireName,
    'target': targetPath,
    'literalUri': literalUri,
    'line': line,
  };

  @override
  int compareTo(ResolvedArchitectureDependency other) {
    final identityOrder = violationIdentity.compareTo(other.violationIdentity);
    if (identityOrder != 0) return identityOrder;
    final literalOrder = literalUri.compareTo(other.literalUri);
    if (literalOrder != 0) return literalOrder;
    return line.compareTo(other.line);
  }
}

class ArchitecturePlacementViolation
    implements Comparable<ArchitecturePlacementViolation> {
  const ArchitecturePlacementViolation({
    required this.path,
    required this.line,
    required this.trigger,
  });

  final String path;
  final int line;
  final String trigger;

  String get identityKey => jsonEncode(<String, Object?>{
    'rule': domainRepositoryPlacementRule,
    'path': path,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'rule': domainRepositoryPlacementRule,
    'path': path,
    'line': line,
    'trigger': trigger,
  };

  @override
  int compareTo(ArchitecturePlacementViolation other) =>
      identityKey.compareTo(other.identityKey);
}

class ArchitectureSourceAnalysis {
  ArchitectureSourceAnalysis({
    required List<ResolvedArchitectureDependency> dependencies,
    required List<ArchitecturePlacementViolation> placementViolations,
    required List<String> fatalIssues,
  }) : dependencies = List.unmodifiable(dependencies..sort()),
       placementViolations = List.unmodifiable(placementViolations..sort()),
       fatalIssues = List.unmodifiable(fatalIssues..sort());

  final List<ResolvedArchitectureDependency> dependencies;
  final List<ArchitecturePlacementViolation> placementViolations;
  final List<String> fatalIssues;

  List<ResolvedArchitectureDependency> get dependencyViolations => dependencies
      .where((dependency) => dependency.violationRule != null)
      .toList(growable: false);
}

ArchitectureLayer architectureLayerForPath(String path) {
  if (path.startsWith('lib/core/')) return ArchitectureLayer.core;
  final segments = p.posix.split(path);
  if (segments.length >= 5 &&
      segments[0] == 'lib' &&
      segments[1] == 'features') {
    return switch (segments[3]) {
      'domain' => ArchitectureLayer.domain,
      'application' => ArchitectureLayer.application,
      'presentation' => ArchitectureLayer.presentation,
      _ => ArchitectureLayer.unclassified,
    };
  }
  if (path.startsWith('lib/shared/widgets/')) {
    return ArchitectureLayer.presentation;
  }
  return ArchitectureLayer.unclassified;
}

String? architectureDependencyRule(String sourcePath, String targetPath) {
  final sourceLayer = architectureLayerForPath(sourcePath);
  final targetLayer = architectureLayerForPath(targetPath);
  if (sourceLayer == ArchitectureLayer.core &&
      targetPath.startsWith('lib/features/')) {
    return coreFeatureDependencyRule;
  }
  if (sourceLayer.rank >= 0 &&
      targetLayer.rank >= 0 &&
      sourceLayer.rank < targetLayer.rank) {
    return upwardLayerDependencyRule;
  }
  return null;
}

class ArchitectureBoundaryChecker {
  ArchitectureBoundaryChecker({
    required String repoRoot,
    required this.manifest,
    GitPathLister? gitPathLister,
  }) : repoRoot = p.normalize(p.absolute(repoRoot)),
       _gitPathLister = gitPathLister ?? listGitVisiblePaths;

  final String repoRoot;
  final ArchitectureBoundaryManifest manifest;
  final GitPathLister _gitPathLister;

  static ArchitectureSourceAnalysis analyzeSourcesForTesting({
    required String packageName,
    required Map<String, String> sources,
  }) {
    final dependencies = <ResolvedArchitectureDependency>[];
    final placements = <ArchitecturePlacementViolation>[];
    final fatalIssues = <String>[];
    final parsedUnits = <String, _ParsedSource>{};
    final sourcePaths = sources.keys.toSet();

    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(packageName)) {
      fatalIssues.add('Invalid root package name: $packageName');
    }
    for (final entry in sources.entries) {
      if (!_isSafeExactPath(entry.key) ||
          !entry.key.startsWith('lib/') ||
          !entry.key.endsWith('.dart')) {
        fatalIssues.add('Unsafe source path: ${entry.key}');
        continue;
      }
      final parsed = parseString(
        content: entry.value,
        path: entry.key,
        throwIfDiagnostics: false,
      );
      if (parsed.errors.isNotEmpty) {
        fatalIssues.add(
          'Parse diagnostics in ${entry.key}: '
          '${parsed.errors.map((error) => error.toString()).join('; ')}',
        );
        continue;
      }
      parsedUnits[entry.key] = _ParsedSource(
        unit: parsed.unit,
        lineInfo: parsed.lineInfo,
      );
    }

    final namedPartOwners = <String, List<String>>{};
    final sortedPaths = parsedUnits.keys.toList()..sort();
    for (final sourcePath in sortedPaths) {
      final parsed = parsedUnits[sourcePath]!;
      for (final directive in parsed.unit.directives) {
        if (directive is! PartDirective) continue;
        final literal = directive.uri.stringValue;
        if (literal == null) {
          fatalIssues.add('$sourcePath has a non-constant part URI.');
          continue;
        }
        final target = _resolveLocalUri(
          packageName: packageName,
          sourcePath: sourcePath,
          literalUri: literal,
          currentPaths: sourcePaths,
          fatalIssues: fatalIssues,
        );
        if (target != null) {
          namedPartOwners.putIfAbsent(target, () => <String>[]).add(sourcePath);
        }
      }
    }
    final repositoryTypeGraph = _RepositoryTypeGraph(parsedUnits);

    for (final sourcePath in sortedPaths) {
      final parsed = parsedUnits[sourcePath]!;
      void addUri(String? literal, int offset, ArchitectureDirectiveKind kind) {
        if (literal == null) {
          fatalIssues.add(
            '$sourcePath has a non-constant ${kind.wireName} URI.',
          );
          return;
        }
        final target = _resolveLocalUri(
          packageName: packageName,
          sourcePath: sourcePath,
          literalUri: literal,
          currentPaths: sourcePaths,
          fatalIssues: fatalIssues,
        );
        if (target == null) return;
        dependencies.add(
          ResolvedArchitectureDependency(
            sourcePath: sourcePath,
            targetPath: target,
            directiveKind: kind,
            literalUri: literal,
            line: parsed.lineInfo.getLocation(offset).lineNumber,
          ),
        );
      }

      for (final directive in parsed.unit.directives) {
        switch (directive) {
          case ImportDirective():
            addUri(
              directive.uri.stringValue,
              directive.uri.offset,
              ArchitectureDirectiveKind.import,
            );
            for (final configuration in directive.configurations) {
              addUri(
                configuration.uri.stringValue,
                configuration.uri.offset,
                ArchitectureDirectiveKind.conditionalImport,
              );
            }
          case ExportDirective():
            addUri(
              directive.uri.stringValue,
              directive.uri.offset,
              ArchitectureDirectiveKind.export,
            );
            for (final configuration in directive.configurations) {
              addUri(
                configuration.uri.stringValue,
                configuration.uri.offset,
                ArchitectureDirectiveKind.conditionalExport,
              );
            }
          case PartDirective():
            addUri(
              directive.uri.stringValue,
              directive.uri.offset,
              ArchitectureDirectiveKind.part,
            );
          case PartOfDirective():
            final literal = directive.uri?.stringValue;
            if (directive.uri != null) {
              addUri(
                literal,
                directive.uri!.offset,
                ArchitectureDirectiveKind.partOf,
              );
            } else {
              final owners = namedPartOwners[sourcePath] ?? const <String>[];
              if (owners.length != 1) {
                fatalIssues.add(
                  '$sourcePath has named part-of '
                  '${directive.libraryName?.name ?? '<unknown>'} with '
                  '${owners.length} matching part directives.',
                );
              } else {
                final declaredName = directive.libraryName?.name ?? '<unknown>';
                final owner = parsedUnits[owners.single]!;
                final ownerLibraryNames = owner.unit.directives
                    .whereType<LibraryDirective>()
                    .map((entry) => entry.name?.name)
                    .whereType<String>()
                    .toList(growable: false);
                if (ownerLibraryNames.length != 1 ||
                    ownerLibraryNames.single != declaredName) {
                  fatalIssues.add(
                    '$sourcePath declares part of $declaredName, but '
                    '${owners.single} does not declare that exact library '
                    'name.',
                  );
                  continue;
                }
                dependencies.add(
                  ResolvedArchitectureDependency(
                    sourcePath: sourcePath,
                    targetPath: owners.single,
                    directiveKind: ArchitectureDirectiveKind.partOf,
                    literalUri:
                        directive.libraryName?.name ?? '<named-part-of>',
                    line: parsed.lineInfo
                        .getLocation(directive.offset)
                        .lineNumber,
                  ),
                );
              }
            }
          default:
            break;
        }
      }

      if (_isFeatureDomainPath(sourcePath)) {
        final triggers = <String>[];
        var line = 1;
        if (p.posix.basename(sourcePath).endsWith('_repository_impl.dart')) {
          triggers.add('filename-suffix');
        }
        for (final candidate in _concreteTypeCandidates(parsed.unit)) {
          final repositoryContract = repositoryTypeGraph.repositoryContractFor(
            originPath: sourcePath,
            references: candidate.references,
          );
          if (!candidate.name.endsWith('RepositoryImpl') &&
              repositoryContract == null) {
            continue;
          }
          triggers.add(
            candidate.name.endsWith('RepositoryImpl')
                ? 'class:${candidate.name}'
                : 'contract:$repositoryContract',
          );
          line = parsed.lineInfo.getLocation(candidate.nameOffset).lineNumber;
        }
        if (triggers.isNotEmpty) {
          final sortedTriggers = triggers.toSet().toList()..sort();
          placements.add(
            ArchitecturePlacementViolation(
              path: sourcePath,
              line: line,
              trigger: sortedTriggers.join(','),
            ),
          );
        }
      }
    }

    return ArchitectureSourceAnalysis(
      dependencies: dependencies,
      placementViolations: placements,
      fatalIssues: fatalIssues,
    );
  }

  ArchitectureBoundaryResult check() {
    final issues = <ArchitectureIssue>[];
    final dependencies = <ResolvedArchitectureDependency>[];
    final placements = <ArchitecturePlacementViolation>[];
    final scannedPaths = <String>[];
    try {
      final listed = _gitPathLister(repoRoot);
      final deleted = listed.deleted.map(_normalizeGitPath).toSet();
      final visible = listed.visible
          .map(_normalizeGitPath)
          .where((path) => !deleted.contains(path))
          .toSet();
      for (final deletedPubspec in deleted.where(
        (path) => path.endsWith('/pubspec.yaml'),
      )) {
        final packageRoot = p.posix.dirname(deletedPubspec);
        final packageLibPrefix = '$packageRoot/lib/';
        if (visible.any(
          (path) => path.startsWith(packageLibPrefix) && path.endsWith('.dart'),
        )) {
          throw FormatException(
            'Deleted package manifest still owns a present lib tree: '
            '$deletedPubspec',
          );
        }
      }
      if (!visible.contains('pubspec.yaml')) {
        throw const FormatException(
          'The root pubspec is a required Git-visible anchor.',
        );
      }
      final pubspecFile = File(p.join(repoRoot, 'pubspec.yaml'));
      _requireContainedEntity(pubspecFile, 'pubspec.yaml');
      final pubspec = loadYamlNode(pubspecFile.readAsStringSync());
      if (pubspec is! YamlMap ||
          pubspec['name'] is! String ||
          (pubspec['name'] as String).trim().isEmpty) {
        throw const FormatException(
          'The root pubspec must contain a non-empty package name.',
        );
      }
      final packageName = (pubspec['name'] as String).trim();
      final nestedPackageRoots = <String>[];
      for (final nestedPubspecPath in visible.where(
        (path) => path.endsWith('/pubspec.yaml'),
      )) {
        final nestedPubspecFile = File(
          p.joinAll(<String>[repoRoot, ...p.posix.split(nestedPubspecPath)]),
        );
        if (!nestedPubspecFile.existsSync()) {
          throw FileSystemException(
            'Git-visible package manifest disappeared during scan.',
            nestedPubspecPath,
          );
        }
        _requireContainedEntity(nestedPubspecFile, nestedPubspecPath);
        final nestedPubspec = loadYamlNode(
          nestedPubspecFile.readAsStringSync(),
        );
        if (nestedPubspec is! YamlMap ||
            nestedPubspec['name'] is! String ||
            (nestedPubspec['name'] as String).trim().isEmpty) {
          throw FormatException(
            'Nested package pubspec has no non-empty name: '
            '$nestedPubspecPath',
          );
        }
        nestedPackageRoots.add(p.posix.dirname(nestedPubspecPath));
      }
      nestedPackageRoots.sort();
      final sourceMap = <String, String>{};
      final dartPaths =
          visible
              .where(
                (path) =>
                    path.startsWith('lib/') &&
                    path.endsWith('.dart') &&
                    !nestedPackageRoots.any(
                      (root) => path == root || path.startsWith('$root/'),
                    ),
              )
              .toList()
            ..sort();
      for (final path in dartPaths) {
        final file = File(
          p.joinAll(<String>[repoRoot, ...p.posix.split(path)]),
        );
        if (!file.existsSync()) {
          throw FileSystemException(
            'Git-visible production source disappeared during scan.',
            path,
          );
        }
        _requireContainedEntity(file, path);
        sourceMap[path] = file.readAsStringSync();
        scannedPaths.add(path);
      }
      final analysis = analyzeSourcesForTesting(
        packageName: packageName,
        sources: sourceMap,
      );
      if (analysis.fatalIssues.isNotEmpty) {
        throw FormatException(analysis.fatalIssues.join('\n'));
      }
      dependencies.addAll(analysis.dependencyViolations);
      placements.addAll(analysis.placementViolations);
      _compareManifest(
        dependencies: dependencies,
        placements: placements,
        issues: issues,
      );
    } on Object catch (error) {
      issues.add(
        ArchitectureIssue(
          kind: ArchitectureIssueKind.untrusted,
          code: 'untrusted-scan',
          message: '$error',
        ),
      );
    }
    return ArchitectureBoundaryResult(
      scannedPaths: scannedPaths,
      dependencyViolations: dependencies,
      placementViolations: placements,
      issues: issues,
    );
  }

  void _compareManifest({
    required List<ResolvedArchitectureDependency> dependencies,
    required List<ArchitecturePlacementViolation> placements,
    required List<ArchitectureIssue> issues,
  }) {
    final actualDependencies = <String, List<ResolvedArchitectureDependency>>{};
    for (final dependency in dependencies) {
      actualDependencies
          .putIfAbsent(
            dependency.violationIdentity,
            () => <ResolvedArchitectureDependency>[],
          )
          .add(dependency);
    }
    final expectedDependencies = <String, DependencyException>{
      for (final exception in manifest.dependencyExceptions)
        exception.identityKey: exception,
    };
    for (final entry in actualDependencies.entries) {
      final dependency = entry.value.first;
      if (entry.value.length != 1 ||
          !expectedDependencies.containsKey(entry.key)) {
        issues.add(
          ArchitectureIssue(
            kind: ArchitectureIssueKind.policy,
            code: entry.value.length == 1
                ? 'new-dependency'
                : 'duplicate-dependency',
            path: dependency.sourcePath,
            line: dependency.line,
            message: entry.key,
          ),
        );
      }
    }
    for (final exception in manifest.dependencyExceptions) {
      if (actualDependencies[exception.identityKey]?.length != 1) {
        issues.add(
          ArchitectureIssue(
            kind: ArchitectureIssueKind.policy,
            code: 'stale-dependency-exception',
            path: exception.source,
            message: exception.identityKey,
          ),
        );
      }
    }

    final actualPlacements = <String, List<ArchitecturePlacementViolation>>{};
    for (final placement in placements) {
      actualPlacements
          .putIfAbsent(
            placement.identityKey,
            () => <ArchitecturePlacementViolation>[],
          )
          .add(placement);
    }
    final expectedPlacements = <String, PlacementException>{
      for (final exception in manifest.placementExceptions)
        exception.identityKey: exception,
    };
    for (final entry in actualPlacements.entries) {
      final placement = entry.value.first;
      if (entry.value.length != 1 ||
          !expectedPlacements.containsKey(entry.key)) {
        issues.add(
          ArchitectureIssue(
            kind: ArchitectureIssueKind.policy,
            code: entry.value.length == 1
                ? 'new-placement'
                : 'duplicate-placement',
            path: placement.path,
            line: placement.line,
            message: entry.key,
          ),
        );
      }
    }
    for (final exception in manifest.placementExceptions) {
      if (actualPlacements[exception.identityKey]?.length != 1) {
        issues.add(
          ArchitectureIssue(
            kind: ArchitectureIssueKind.policy,
            code: 'stale-placement-exception',
            path: exception.path,
            message: exception.identityKey,
          ),
        );
      }
    }
  }

  void _requireContainedEntity(FileSystemEntity entity, String displayPath) {
    final resolvedRoot = Directory(repoRoot).resolveSymbolicLinksSync();
    final absolute = p.normalize(p.absolute(entity.path));
    if (absolute != repoRoot && !p.isWithin(repoRoot, absolute)) {
      throw FormatException('Path escapes repository: $displayPath');
    }
    final resolved = entity.resolveSymbolicLinksSync();
    if (resolved != resolvedRoot && !p.isWithin(resolvedRoot, resolved)) {
      throw FormatException('Symlink escapes repository: $displayPath');
    }
    final relative = p.posix.joinAll(
      p.split(p.relative(resolved, from: resolvedRoot)),
    );
    if (relative != displayPath) {
      throw FormatException(
        'Git path case or spelling does not match the filesystem: $displayPath',
      );
    }
  }

  static GitVisiblePaths listGitVisiblePaths(
    String repoRoot, {
    Map<String, String>? environment,
  }) {
    final gitEnvironment = environment ?? Platform.environment;
    validateArchitectureGitEnvironment(gitEnvironment);

    List<int> run(List<String> arguments) {
      final result = Process.runSync(
        'git',
        <String>['-C', repoRoot, ...arguments],
        stdoutEncoding: null,
        stderrEncoding: utf8,
        environment: gitEnvironment,
        includeParentEnvironment: false,
      );
      if (result.exitCode != 0) {
        throw FileSystemException(
          'git ${arguments.join(' ')} failed (${result.exitCode}): '
          '${result.stderr}',
          repoRoot,
        );
      }
      return result.stdout as List<int>;
    }

    String runLine(List<String> arguments) {
      final bytes = run(arguments);
      var end = bytes.length;
      if (end > 0 && bytes[end - 1] == 10) end--;
      if (end > 0 && bytes[end - 1] == 13) end--;
      final lineBytes = bytes.sublist(0, end);
      final line = utf8.decode(lineBytes);
      if (line.isEmpty ||
          lineBytes.contains(0) ||
          line.contains('\n') ||
          line.contains('\r')) {
        throw FormatException(
          'Git emitted an invalid response for ${arguments.join(' ')}.',
        );
      }
      return line;
    }

    final expectedRoot = Directory(repoRoot).resolveSymbolicLinksSync();
    final reportedRoot = Directory(
      runLine(const <String>['rev-parse', '--show-toplevel']),
    ).resolveSymbolicLinksSync();
    if (!p.equals(expectedRoot, reportedRoot)) {
      throw FormatException(
        'Git work tree does not match repository root: $reportedRoot',
      );
    }
    if (runLine(const <String>['rev-parse', '--is-inside-work-tree']) !=
        'true') {
      throw const FormatException('Repository root is not a Git work tree.');
    }
    final expectedGitDirectory = _resolveGitDirectory(repoRoot);
    final reportedGitDirectory = Directory(
      runLine(const <String>['rev-parse', '--absolute-git-dir']),
    ).resolveSymbolicLinksSync();
    if (!p.equals(expectedGitDirectory, reportedGitDirectory)) {
      throw FormatException(
        'Git directory does not match repository anchor: '
        '$reportedGitDirectory',
      );
    }
    final reportedIndex = runLine(const <String>[
      'rev-parse',
      '--git-path',
      'index',
    ]);
    final absoluteReportedIndex = p.normalize(
      p.absolute(
        p.isAbsolute(reportedIndex)
            ? reportedIndex
            : p.join(repoRoot, reportedIndex),
      ),
    );
    final indexFile = File(absoluteReportedIndex);
    final resolvedIndex = indexFile.existsSync()
        ? indexFile.resolveSymbolicLinksSync()
        : p.join(
            Directory(
              p.dirname(absoluteReportedIndex),
            ).resolveSymbolicLinksSync(),
            p.basename(absoluteReportedIndex),
          );
    final expectedIndex = p.normalize(
      p.absolute(p.join(reportedGitDirectory, 'index')),
    );
    if (!p.equals(resolvedIndex, expectedIndex)) {
      throw FormatException(
        'Git index does not match repository Git directory: $resolvedIndex',
      );
    }

    List<String> runPaths(List<String> arguments) {
      final bytes = run(arguments);
      final paths = <String>[];
      var start = 0;
      for (var index = 0; index < bytes.length; index++) {
        if (bytes[index] != 0) continue;
        if (index > start) {
          paths.add(utf8.decode(bytes.sublist(start, index)));
        }
        start = index + 1;
      }
      if (start != bytes.length) {
        throw const FormatException('Git emitted a non-NUL-terminated path.');
      }
      return paths;
    }

    return GitVisiblePaths(
      visible: runPaths(const <String>[
        'ls-files',
        '-z',
        '--cached',
        '--others',
        '--exclude-standard',
      ]),
      deleted: runPaths(const <String>['ls-files', '-z', '--deleted']),
    );
  }
}

class DependencyException implements Comparable<DependencyException> {
  const DependencyException({
    required this.rule,
    required this.sourceLayer,
    required this.targetLayer,
    required this.source,
    required this.directiveKind,
    required this.target,
    required this.count,
    required this.owner,
    required this.reason,
    required this.evidence,
    required this.condition,
  });

  factory DependencyException.fromJson(Object? value) {
    final json = _strictObject(value, 'dependency exception', const <String>{
      'rule',
      'sourceLayer',
      'targetLayer',
      'source',
      'directiveKind',
      'target',
      'count',
      'owner',
      'reason',
      'evidence',
      'condition',
    });
    final rule = _requiredString(json, 'rule');
    if (rule != coreFeatureDependencyRule &&
        rule != upwardLayerDependencyRule) {
      throw FormatException('Unknown dependency rule: $rule');
    }
    final source = _requiredExactPath(json, 'source');
    final target = _requiredExactPath(json, 'target');
    final sourceLayer = ArchitectureLayer.parse(
      _requiredString(json, 'sourceLayer'),
    );
    final targetLayer = ArchitectureLayer.parse(
      _requiredString(json, 'targetLayer'),
    );
    final directiveKind = ArchitectureDirectiveKind.parse(
      _requiredString(json, 'directiveKind'),
    );
    if (architectureLayerForPath(source) != sourceLayer ||
        architectureLayerForPath(target) != targetLayer) {
      throw FormatException(
        'Dependency exception layers do not match their exact paths: '
        '$source -> $target',
      );
    }
    if (architectureDependencyRule(source, target) != rule) {
      throw FormatException(
        'Dependency exception rule does not match its exact paths: '
        '$source -> $target',
      );
    }
    if (json['count'] is! int || json['count'] != 1) {
      throw const FormatException(
        'Dependency exception count must be exactly 1.',
      );
    }
    return DependencyException(
      rule: rule,
      sourceLayer: sourceLayer,
      targetLayer: targetLayer,
      source: source,
      directiveKind: directiveKind,
      target: target,
      count: 1,
      owner: _requiredMetadata(json, 'owner'),
      reason: _requiredMetadata(json, 'reason'),
      evidence: _requiredMetadata(json, 'evidence'),
      condition: _requiredMetadata(json, 'condition'),
    );
  }

  final String rule;
  final ArchitectureLayer sourceLayer;
  final ArchitectureLayer targetLayer;
  final String source;
  final ArchitectureDirectiveKind directiveKind;
  final String target;
  final int count;
  final String owner;
  final String reason;
  final String evidence;
  final String condition;

  String get identityKey => jsonEncode(<String, Object?>{
    'rule': rule,
    'source': source,
    'directiveKind': directiveKind.wireName,
    'target': target,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'rule': rule,
    'sourceLayer': sourceLayer.wireName,
    'targetLayer': targetLayer.wireName,
    'source': source,
    'directiveKind': directiveKind.wireName,
    'target': target,
    'count': count,
    'owner': owner,
    'reason': reason,
    'evidence': evidence,
    'condition': condition,
  };

  @override
  int compareTo(DependencyException other) =>
      identityKey.compareTo(other.identityKey);
}

class PlacementException implements Comparable<PlacementException> {
  const PlacementException({
    required this.rule,
    required this.path,
    required this.owner,
    required this.reason,
    required this.evidence,
    required this.condition,
  });

  factory PlacementException.fromJson(Object? value) {
    final json = _strictObject(value, 'placement exception', const <String>{
      'rule',
      'path',
      'owner',
      'reason',
      'evidence',
      'condition',
    });
    final rule = _requiredString(json, 'rule');
    if (rule != domainRepositoryPlacementRule) {
      throw FormatException('Unknown placement rule: $rule');
    }
    final path = _requiredExactPath(json, 'path');
    if (!_isFeatureDomainPath(path)) {
      throw FormatException(
        'Placement exception must be an exact feature-domain path: $path',
      );
    }
    return PlacementException(
      rule: rule,
      path: path,
      owner: _requiredMetadata(json, 'owner'),
      reason: _requiredMetadata(json, 'reason'),
      evidence: _requiredMetadata(json, 'evidence'),
      condition: _requiredMetadata(json, 'condition'),
    );
  }

  final String rule;
  final String path;
  final String owner;
  final String reason;
  final String evidence;
  final String condition;

  String get identityKey =>
      jsonEncode(<String, Object?>{'rule': rule, 'path': path});

  Map<String, Object?> toJson() => <String, Object?>{
    'rule': rule,
    'path': path,
    'owner': owner,
    'reason': reason,
    'evidence': evidence,
    'condition': condition,
  };

  @override
  int compareTo(PlacementException other) =>
      identityKey.compareTo(other.identityKey);
}

class ArchitectureBoundaryManifest {
  ArchitectureBoundaryManifest._({
    required this.dependencyExceptions,
    required this.placementExceptions,
  });

  factory ArchitectureBoundaryManifest.fromJsonString(String source) {
    _DuplicateKeyJsonValidator(source).validate();
    final decoded = jsonDecode(source);
    final json = _strictObject(
      decoded,
      'architecture boundary manifest',
      const <String>{
        'schemaVersion',
        'policy',
        'dependencyExceptions',
        'placementExceptions',
      },
    );
    if (json['schemaVersion'] != 1) {
      throw const FormatException('schemaVersion must be exactly 1.');
    }
    final policy = _strictObject(json['policy'], 'policy', const <String>{
      'layers',
      'rules',
    });
    final layers = _requiredStringList(policy, 'layers');
    final rules = _requiredStringList(policy, 'rules');
    if (!_listEquals(layers, architecturePolicyLayers) ||
        !_listEquals(rules, architecturePolicyRules)) {
      throw const FormatException(
        'Policy layers and rules must match the DTR-12 schema exactly.',
      );
    }
    final rawDependencies = json['dependencyExceptions'];
    final rawPlacements = json['placementExceptions'];
    if (rawDependencies is! List || rawPlacements is! List) {
      throw const FormatException(
        'dependencyExceptions and placementExceptions must be arrays.',
      );
    }
    final dependencies =
        rawDependencies
            .map(DependencyException.fromJson)
            .toList(growable: false)
          ..sort();
    final placements =
        rawPlacements.map(PlacementException.fromJson).toList(growable: false)
          ..sort();
    _rejectDuplicateIdentities(
      dependencies.map((entry) => entry.identityKey),
      'dependency exception',
    );
    _rejectDuplicateIdentities(
      placements.map((entry) => entry.identityKey),
      'placement exception',
    );
    return ArchitectureBoundaryManifest._(
      dependencyExceptions: List.unmodifiable(dependencies),
      placementExceptions: List.unmodifiable(placements),
    );
  }

  factory ArchitectureBoundaryManifest.empty() =>
      ArchitectureBoundaryManifest._(
        dependencyExceptions: const <DependencyException>[],
        placementExceptions: const <PlacementException>[],
      );

  static ArchitectureBoundaryManifest loadSync(File file) =>
      ArchitectureBoundaryManifest.fromJsonString(file.readAsStringSync());

  final List<DependencyException> dependencyExceptions;
  final List<PlacementException> placementExceptions;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'policy': <String, Object?>{
      'layers': architecturePolicyLayers,
      'rules': architecturePolicyRules,
    },
    'dependencyExceptions': dependencyExceptions
        .map((entry) => entry.toJson())
        .toList(growable: false),
    'placementExceptions': placementExceptions
        .map((entry) => entry.toJson())
        .toList(growable: false),
  };
}

class ArchitectureBoundaryResult {
  ArchitectureBoundaryResult({
    required List<String> scannedPaths,
    required List<ResolvedArchitectureDependency> dependencyViolations,
    required List<ArchitecturePlacementViolation> placementViolations,
    required List<ArchitectureIssue> issues,
  }) : scannedPaths = List.unmodifiable(scannedPaths..sort()),
       dependencyViolations = List.unmodifiable(dependencyViolations..sort()),
       placementViolations = List.unmodifiable(placementViolations..sort()),
       issues = List.unmodifiable(issues..sort());

  final List<String> scannedPaths;
  final List<ResolvedArchitectureDependency> dependencyViolations;
  final List<ArchitecturePlacementViolation> placementViolations;
  final List<ArchitectureIssue> issues;

  bool get trustworthy =>
      !issues.any((issue) => issue.kind == ArchitectureIssueKind.untrusted);
  bool get hasPolicyDrift =>
      issues.any((issue) => issue.kind == ArchitectureIssueKind.policy);
  bool get exact => trustworthy && !hasPolicyDrift;

  int exitCodeFor({required bool check}) {
    if (!trustworthy) return 2;
    if (check && hasPolicyDrift) return 1;
    return 0;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'trustworthy': trustworthy,
    'drift': hasPolicyDrift,
    'exact': exact,
    'counts': <String, Object?>{
      'sources': scannedPaths.length,
      'dependencyViolations': dependencyViolations.length,
      'placementViolations': placementViolations.length,
      'issues': issues.length,
    },
    'dependencyViolations': dependencyViolations
        .map((dependency) => dependency.toJson())
        .toList(growable: false),
    'placementViolations': placementViolations
        .map((placement) => placement.toJson())
        .toList(growable: false),
    'issues': issues.map((issue) => issue.toJson()).toList(growable: false),
  };

  String toJsonText() => const JsonEncoder.withIndent('  ').convert(toJson());

  String toText() {
    final buffer = StringBuffer()
      ..writeln(
        'architecture-boundaries: '
        '${trustworthy ? (exact ? 'exact' : 'drift') : 'untrustworthy'}',
      )
      ..writeln('sources: ${scannedPaths.length}')
      ..writeln('dependency violations: ${dependencyViolations.length}')
      ..writeln('placement violations: ${placementViolations.length}')
      ..writeln('issues: ${issues.length}');
    for (final issue in issues) {
      buffer.writeln(issue);
    }
    return buffer.toString().trimRight();
  }
}

class GitVisiblePaths {
  const GitVisiblePaths({required this.visible, required this.deleted});

  final List<String> visible;
  final List<String> deleted;
}

typedef GitPathLister = GitVisiblePaths Function(String repoRoot);

void validateArchitectureGitEnvironment(Map<String, String> environment) {
  const redirects = <String>{
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
  };
  final rejected =
      environment.keys
          .where(
            (key) =>
                redirects.contains(key) ||
                key == 'GIT_CONFIG_PARAMETERS' ||
                key.startsWith('GIT_CONFIG_'),
          )
          .toList()
        ..sort();
  if (rejected.isNotEmpty) {
    throw FormatException(
      'Git repository redirection environment is not allowed: '
      '${rejected.join(', ')}',
    );
  }
}

class _ParsedSource {
  const _ParsedSource({required this.unit, required this.lineInfo});

  final CompilationUnit unit;
  final dynamic lineInfo;
}

class _ConcreteTypeCandidate {
  const _ConcreteTypeCandidate({
    required this.name,
    required this.nameOffset,
    required this.references,
  });

  final String name;
  final int nameOffset;
  final List<String> references;
}

Iterable<_ConcreteTypeCandidate> _concreteTypeCandidates(
  CompilationUnit unit,
) sync* {
  for (final declaration in unit.declarations) {
    switch (declaration) {
      case ClassDeclaration():
        if (declaration.abstractKeyword != null ||
            declaration.sealedKeyword != null) {
          continue;
        }
        yield _ConcreteTypeCandidate(
          name: declaration.name.lexeme,
          nameOffset: declaration.name.offset,
          references: _classDeclarationReferences(declaration),
        );
      case ClassTypeAlias():
        if (declaration.abstractKeyword != null ||
            declaration.sealedKeyword != null) {
          continue;
        }
        yield _ConcreteTypeCandidate(
          name: declaration.name.lexeme,
          nameOffset: declaration.name.offset,
          references: _classTypeAliasReferences(declaration),
        );
      default:
        break;
    }
  }
}

List<String> _classDeclarationReferences(
  ClassDeclaration declaration,
) => <String>[
  if (declaration.extendsClause?.superclass case final superclass?)
    superclass.name.lexeme,
  ...?declaration.withClause?.mixinTypes.map((type) => type.name.lexeme),
  ...?declaration.implementsClause?.interfaces.map((type) => type.name.lexeme),
];

List<String> _classTypeAliasReferences(ClassTypeAlias declaration) => <String>[
  declaration.superclass.name.lexeme,
  ...declaration.withClause.mixinTypes.map((type) => type.name.lexeme),
  ...?declaration.implementsClause?.interfaces.map((type) => type.name.lexeme),
];

class _RepositoryTypeNode {
  const _RepositoryTypeNode({
    required this.path,
    required this.name,
    required this.references,
  });

  final String path;
  final String name;
  final List<String> references;

  String get identity => '$path::$name';
}

class _RepositoryTypeGraph {
  _RepositoryTypeGraph(Map<String, _ParsedSource> sources) {
    for (final entry in sources.entries) {
      for (final declaration in entry.value.unit.declarations) {
        final node = switch (declaration) {
          ClassDeclaration() => _RepositoryTypeNode(
            path: entry.key,
            name: declaration.name.lexeme,
            references: _classDeclarationReferences(declaration),
          ),
          ClassTypeAlias() => _RepositoryTypeNode(
            path: entry.key,
            name: declaration.name.lexeme,
            references: _classTypeAliasReferences(declaration),
          ),
          GenericTypeAlias(type: final NamedType type) => _RepositoryTypeNode(
            path: entry.key,
            name: declaration.name.lexeme,
            references: <String>[type.name.lexeme],
          ),
          MixinDeclaration() => _RepositoryTypeNode(
            path: entry.key,
            name: declaration.name.lexeme,
            references: <String>[
              ...?declaration.implementsClause?.interfaces.map(
                (type) => type.name.lexeme,
              ),
            ],
          ),
          _ => null,
        };
        if (node != null) {
          _nodesByName
              .putIfAbsent(node.name, () => <_RepositoryTypeNode>[])
              .add(node);
        }
      }
    }
    for (final nodes in _nodesByName.values) {
      nodes.sort((left, right) => left.identity.compareTo(right.identity));
    }
  }

  final Map<String, List<_RepositoryTypeNode>> _nodesByName =
      <String, List<_RepositoryTypeNode>>{};

  String? repositoryContractFor({
    required String originPath,
    required Iterable<String> references,
  }) {
    for (final reference in references) {
      final contract = _resolveReference(
        reference: reference,
        originPath: originPath,
        visited: <String>{},
      );
      if (contract != null) return contract;
    }
    return null;
  }

  String? _resolveReference({
    required String reference,
    required String originPath,
    required Set<String> visited,
  }) {
    if (reference.endsWith('Repository')) return reference;
    final candidates = _nodesByName[reference] ?? const <_RepositoryTypeNode>[];
    final localCandidates = candidates
        .where((candidate) => candidate.path == originPath)
        .toList(growable: false);
    final resolvable = localCandidates.isNotEmpty
        ? localCandidates
        : candidates;
    if (resolvable.length != 1) return null;
    final node = resolvable.single;
    if (!visited.add(node.identity)) return null;
    for (final ancestor in node.references) {
      final contract = _resolveReference(
        reference: ancestor,
        originPath: node.path,
        visited: visited,
      );
      if (contract != null) return contract;
    }
    return null;
  }
}

String? _resolveLocalUri({
  required String packageName,
  required String sourcePath,
  required String literalUri,
  required Set<String> currentPaths,
  required List<String> fatalIssues,
}) {
  if (literalUri.isEmpty ||
      literalUri.contains('\\') ||
      literalUri.contains('%')) {
    fatalIssues.add('$sourcePath has an unsafe local URI: $literalUri');
    return null;
  }
  final uri = Uri.tryParse(literalUri);
  if (uri == null) {
    fatalIssues.add('$sourcePath has an invalid URI: $literalUri');
    return null;
  }
  if (uri.scheme == 'dart') return null;
  String? target;
  if (uri.scheme == 'package') {
    final segments = uri.pathSegments;
    if (segments.isEmpty || segments.first != packageName) return null;
    if (uri.hasQuery || uri.hasFragment || segments.length < 2) {
      fatalIssues.add('$sourcePath has an unsafe local URI: $literalUri');
      return null;
    }
    target = p.posix.joinAll(<String>['lib', ...segments.skip(1)]);
  } else if (uri.hasScheme || literalUri.startsWith('/')) {
    fatalIssues.add('$sourcePath has an unsafe URI scheme: $literalUri');
    return null;
  } else {
    if (uri.hasQuery || uri.hasFragment) {
      fatalIssues.add('$sourcePath has an unsafe local URI: $literalUri');
      return null;
    }
    target = p.posix.normalize(
      p.posix.join(p.posix.dirname(sourcePath), uri.path),
    );
  }
  if (!_isSafeExactPath(target) ||
      !target.startsWith('lib/') ||
      !target.endsWith('.dart')) {
    fatalIssues.add(
      '$sourcePath has an escaping or unsafe local URI: $literalUri',
    );
    return null;
  }
  if (!currentPaths.contains(target)) {
    fatalIssues.add(
      '$sourcePath has an unresolved or case-mismatched local URI: '
      '$literalUri -> $target',
    );
    return null;
  }
  return target;
}

bool _isFeatureDomainPath(String path) {
  final segments = p.posix.split(path);
  return segments.length >= 5 &&
      segments[0] == 'lib' &&
      segments[1] == 'features' &&
      segments[3] == 'domain' &&
      path.endsWith('.dart');
}

String _normalizeGitPath(String rawPath) {
  if (!_isSafeExactPath(rawPath)) {
    throw FormatException('Unsafe Git path: $rawPath');
  }
  return rawPath;
}

bool _isSafeExactPath(String path) {
  if (path.isEmpty ||
      path.contains('*') ||
      path.contains('?') ||
      path.contains('[') ||
      path.contains('\\') ||
      path.contains('\u0000') ||
      p.posix.isAbsolute(path)) {
    return false;
  }
  final normalized = p.posix.normalize(path);
  return normalized == path &&
      normalized != '.' &&
      normalized != '..' &&
      !normalized.startsWith('../');
}

String _requiredExactPath(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  if (!_isSafeExactPath(value) ||
      !value.startsWith('lib/') ||
      !value.endsWith('.dart')) {
    throw FormatException('$key must be an exact lib Dart path: $value');
  }
  return value;
}

String _requiredMetadata(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  if (value.contains('*') || value.contains('?') || value.contains('[')) {
    throw FormatException('$key cannot contain wildcard/glob syntax.');
  }
  return value;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty || value != value.trim()) {
    throw FormatException('$key must be a trimmed non-empty string.');
  }
  return value;
}

List<String> _requiredStringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List ||
      value.any(
        (entry) =>
            entry is! String || entry.trim().isEmpty || entry != entry.trim(),
      )) {
    throw FormatException('$key must be a list of trimmed non-empty strings.');
  }
  return value.cast<String>();
}

class _DuplicateKeyJsonValidator {
  _DuplicateKeyJsonValidator(this.source);

  final String source;
  var _offset = 0;

  void validate() {
    _skipWhitespace();
    _parseValue();
    _skipWhitespace();
    if (_offset != source.length) {
      _fail('Unexpected trailing JSON content');
    }
  }

  void _parseValue() {
    _skipWhitespace();
    if (_offset >= source.length) _fail('Unexpected end of JSON input');
    switch (source.codeUnitAt(_offset)) {
      case 0x7b:
        _parseObject();
      case 0x5b:
        _parseArray();
      case 0x22:
        _parseString();
      case 0x74:
        _consumeLiteral('true');
      case 0x66:
        _consumeLiteral('false');
      case 0x6e:
        _consumeLiteral('null');
      default:
        _parseNumber();
    }
  }

  void _parseObject() {
    _offset++;
    _skipWhitespace();
    if (_consumeIf(0x7d)) return;
    final keys = <String>{};
    while (true) {
      _skipWhitespace();
      if (_offset >= source.length || source.codeUnitAt(_offset) != 0x22) {
        _fail('JSON object keys must be strings');
      }
      final key = _parseString();
      if (!keys.add(key)) {
        throw FormatException('Duplicate JSON object key: $key');
      }
      _skipWhitespace();
      if (!_consumeIf(0x3a)) _fail('Expected colon after JSON object key');
      _parseValue();
      _skipWhitespace();
      if (_consumeIf(0x7d)) return;
      if (!_consumeIf(0x2c)) _fail('Expected comma in JSON object');
    }
  }

  void _parseArray() {
    _offset++;
    _skipWhitespace();
    if (_consumeIf(0x5d)) return;
    while (true) {
      _parseValue();
      _skipWhitespace();
      if (_consumeIf(0x5d)) return;
      if (!_consumeIf(0x2c)) _fail('Expected comma in JSON array');
    }
  }

  String _parseString() {
    final start = _offset;
    _offset++;
    while (_offset < source.length) {
      final codeUnit = source.codeUnitAt(_offset);
      if (codeUnit == 0x22) {
        _offset++;
        final value = jsonDecode(source.substring(start, _offset));
        if (value is! String) _fail('Invalid JSON string');
        return value;
      }
      if (codeUnit < 0x20) _fail('Control character in JSON string');
      if (codeUnit != 0x5c) {
        _offset++;
        continue;
      }
      _offset++;
      if (_offset >= source.length) _fail('Incomplete JSON string escape');
      final escape = source.codeUnitAt(_offset);
      if (escape == 0x75) {
        if (_offset + 4 >= source.length) {
          _fail('Incomplete JSON Unicode escape');
        }
        for (var index = _offset + 1; index <= _offset + 4; index++) {
          if (!_isHexDigit(source.codeUnitAt(index))) {
            _fail('Invalid JSON Unicode escape');
          }
        }
        _offset += 5;
      } else {
        if (!const <int>{
          0x22,
          0x5c,
          0x2f,
          0x62,
          0x66,
          0x6e,
          0x72,
          0x74,
        }.contains(escape)) {
          _fail('Invalid JSON string escape');
        }
        _offset++;
      }
    }
    _fail('Unterminated JSON string');
  }

  void _parseNumber() {
    final start = _offset;
    while (_offset < source.length) {
      final codeUnit = source.codeUnitAt(_offset);
      if ((codeUnit >= 0x30 && codeUnit <= 0x39) ||
          codeUnit == 0x2d ||
          codeUnit == 0x2b ||
          codeUnit == 0x2e ||
          codeUnit == 0x45 ||
          codeUnit == 0x65) {
        _offset++;
      } else {
        break;
      }
    }
    if (_offset == start) _fail('Invalid JSON value');
    final token = source.substring(start, _offset);
    try {
      if (jsonDecode(token) is! num) _fail('Invalid JSON number');
    } on FormatException {
      _fail('Invalid JSON number');
    }
  }

  void _consumeLiteral(String literal) {
    if (!source.startsWith(literal, _offset)) {
      _fail('Invalid JSON literal');
    }
    _offset += literal.length;
  }

  bool _consumeIf(int codeUnit) {
    if (_offset < source.length && source.codeUnitAt(_offset) == codeUnit) {
      _offset++;
      return true;
    }
    return false;
  }

  void _skipWhitespace() {
    while (_offset < source.length) {
      final codeUnit = source.codeUnitAt(_offset);
      if (codeUnit != 0x20 &&
          codeUnit != 0x09 &&
          codeUnit != 0x0a &&
          codeUnit != 0x0d) {
        return;
      }
      _offset++;
    }
  }

  Never _fail(String message) {
    throw FormatException('$message at offset $_offset.');
  }
}

bool _isHexDigit(int codeUnit) =>
    (codeUnit >= 0x30 && codeUnit <= 0x39) ||
    (codeUnit >= 0x41 && codeUnit <= 0x46) ||
    (codeUnit >= 0x61 && codeUnit <= 0x66);

Map<String, Object?> _strictObject(
  Object? value,
  String label,
  Set<String> allowedKeys,
) {
  if (value is! Map) throw FormatException('$label must be a JSON object.');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String || !allowedKeys.contains(entry.key)) {
      throw FormatException('Unknown $label key: ${entry.key}');
    }
    result[entry.key as String] = entry.value;
  }
  final missing = allowedKeys.difference(result.keys.toSet());
  if (missing.isNotEmpty) {
    throw FormatException('$label is missing keys: ${missing.join(', ')}');
  }
  return result;
}

void _rejectDuplicateIdentities(Iterable<String> identities, String label) {
  final seen = <String>{};
  for (final identity in identities) {
    if (!seen.add(identity)) {
      throw FormatException('Duplicate $label identity: $identity');
    }
  }
}

bool _listEquals(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

String _resolveGitDirectory(String repoRoot) {
  final markerPath = p.join(repoRoot, '.git');
  final directory = Directory(markerPath);
  if (directory.existsSync()) return directory.resolveSymbolicLinksSync();
  final markerFile = File(markerPath);
  if (!markerFile.existsSync()) {
    throw FileSystemException(
      'Repository has no .git directory or gitdir file.',
      markerPath,
    );
  }
  var marker = markerFile.readAsStringSync();
  if (marker.endsWith('\n')) marker = marker.substring(0, marker.length - 1);
  if (marker.endsWith('\r')) marker = marker.substring(0, marker.length - 1);
  const prefix = 'gitdir: ';
  if (!marker.startsWith(prefix) ||
      marker.length == prefix.length ||
      marker.contains('\n') ||
      marker.contains('\r')) {
    throw FormatException('Malformed .git gitdir file: $markerPath');
  }
  final reference = marker.substring(prefix.length);
  final gitDirectory = Directory(
    p.isAbsolute(reference)
        ? reference
        : p.normalize(p.join(repoRoot, reference)),
  );
  if (!gitDirectory.existsSync()) {
    throw FileSystemException(
      'Referenced Git directory does not exist.',
      gitDirectory.path,
    );
  }
  return gitDirectory.resolveSymbolicLinksSync();
}
