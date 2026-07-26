import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

enum SuppressionIssueKind { policy, untrusted }

class SuppressionIssue implements Comparable<SuppressionIssue> {
  const SuppressionIssue({
    required this.kind,
    required this.code,
    required this.message,
    this.path,
    this.line,
  });

  final SuppressionIssueKind kind;
  final String code;
  final String message;
  final String? path;
  final int? line;

  @override
  int compareTo(SuppressionIssue other) {
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

enum SuppressionDirectiveKind {
  ignore('ignore'),
  ignoreForFile('ignore_for_file');

  const SuppressionDirectiveKind(this.wireName);
  final String wireName;

  static SuppressionDirectiveKind parse(String value) => values.firstWhere(
    (entry) => entry.wireName == value,
    orElse: () => throw FormatException('Unknown directive kind: $value'),
  );
}

class TargetFingerprint implements Comparable<TargetFingerprint> {
  const TargetFingerprint({
    required this.kind,
    required this.ownerChain,
    required this.name,
    required this.signature,
  });

  factory TargetFingerprint.fromJson(Object? value) {
    final json = _strictObject(value, 'targetFingerprint', const <String>{
      'kind',
      'ownerChain',
      'name',
      'signature',
    });
    final kind = _requiredString(json, 'kind');
    if (!const <String>{
      'import',
      'function',
      'method',
      'variable',
      'constructor',
      'class',
      'mixin',
      'enum',
      'extension',
      'extension-type',
      'type-alias',
    }.contains(kind)) {
      throw FormatException('Unknown target fingerprint kind: $kind');
    }
    final ownerChain = _requiredStringList(json, 'ownerChain');
    final name = _requiredString(json, 'name');
    final signature = _requiredString(json, 'signature');
    if (<String>[...ownerChain, name, signature].any(_containsWildcard)) {
      throw const FormatException(
        'Target fingerprints cannot contain wildcard/glob fields.',
      );
    }
    return TargetFingerprint(
      kind: kind,
      ownerChain: ownerChain,
      name: name,
      signature: signature,
    );
  }

  final String kind;
  final List<String> ownerChain;
  final String name;
  final String signature;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'ownerChain': ownerChain,
    'name': name,
    'signature': signature,
  };

  String get stableKey => jsonEncode(toJson());

  @override
  int compareTo(TargetFingerprint other) =>
      stableKey.compareTo(other.stableKey);

  @override
  bool operator ==(Object other) =>
      other is TargetFingerprint && stableKey == other.stableKey;

  @override
  int get hashCode => stableKey.hashCode;
}

class SuppressionOccurrence implements Comparable<SuppressionOccurrence> {
  const SuppressionOccurrence({
    required this.path,
    required this.directiveKind,
    required this.diagnostic,
    required this.targetFingerprint,
    required this.count,
    required this.line,
  });

  final String path;
  final SuppressionDirectiveKind directiveKind;
  final String diagnostic;
  final TargetFingerprint targetFingerprint;
  final int count;
  final int line;

  String get identityKey => jsonEncode(<String, Object?>{
    'path': path,
    'directiveKind': directiveKind.wireName,
    'diagnostic': diagnostic,
    'targetFingerprint': targetFingerprint.toJson(),
    'count': count,
  });

  @override
  int compareTo(SuppressionOccurrence other) =>
      identityKey.compareTo(other.identityKey);
}

class SuppressionInventoryEntry
    implements Comparable<SuppressionInventoryEntry> {
  const SuppressionInventoryEntry({
    required this.path,
    required this.directiveKind,
    required this.diagnostic,
    required this.targetFingerprint,
    required this.count,
    required this.sourceKind,
    required this.ownerKind,
    required this.ownerId,
    required this.reason,
    required this.evidence,
    required this.removalCondition,
  });

  factory SuppressionInventoryEntry.fromJson(Object? value) {
    final json = _strictObject(value, 'inventory entry', const <String>{
      'path',
      'directiveKind',
      'diagnostic',
      'targetFingerprint',
      'count',
      'sourceKind',
      'owner',
      'reason',
      'evidence',
      'removalCondition',
    });
    final path = _requiredString(json, 'path');
    if (!_isSafeExactPath(path)) {
      throw FormatException('Inventory path must be exact: $path');
    }
    final diagnostic = _requiredString(json, 'diagnostic').toLowerCase();
    if (!RegExp(r'^unused_[a-z0-9_]+$').hasMatch(diagnostic)) {
      throw FormatException(
        'Inventory diagnostic must be an unused_* code: $diagnostic',
      );
    }
    final directiveKind = SuppressionDirectiveKind.parse(
      _requiredString(json, 'directiveKind'),
    );
    if (directiveKind != SuppressionDirectiveKind.ignore) {
      throw const FormatException(
        'File-wide suppressions cannot be inventoried.',
      );
    }
    final count = json['count'];
    if (count is! int || count != 1) {
      throw const FormatException('Inventory entry count must be exactly 1.');
    }
    final sourceKind = _requiredString(json, 'sourceKind');
    if (sourceKind != 'generated' && sourceKind != 'handwritten') {
      throw FormatException('Unknown sourceKind: $sourceKind');
    }
    final owner = _strictObject(json['owner'], 'owner', const <String>{
      'kind',
      'id',
    });
    final ownerKind = _requiredString(owner, 'kind');
    if (ownerKind != 'generator' && ownerKind != 'roadmap') {
      throw FormatException('Unknown owner kind: $ownerKind');
    }
    final evidence = _requiredStringList(json, 'evidence');
    if (evidence.isEmpty) {
      throw const FormatException('Inventory evidence must not be empty.');
    }
    final ownerId = _requiredString(owner, 'id');
    if (_containsWildcard(ownerId) ||
        (sourceKind == 'generated' && ownerKind != 'generator') ||
        (sourceKind == 'handwritten' && ownerKind != 'roadmap')) {
      throw const FormatException(
        'Source kind and exact owner kind/id must be compatible.',
      );
    }
    return SuppressionInventoryEntry(
      path: path,
      directiveKind: directiveKind,
      diagnostic: diagnostic,
      targetFingerprint: TargetFingerprint.fromJson(json['targetFingerprint']),
      count: count,
      sourceKind: sourceKind,
      ownerKind: ownerKind,
      ownerId: ownerId,
      reason: _requiredString(json, 'reason'),
      evidence: List<String>.unmodifiable(evidence),
      removalCondition: _requiredString(json, 'removalCondition'),
    );
  }

  final String path;
  final SuppressionDirectiveKind directiveKind;
  final String diagnostic;
  final TargetFingerprint targetFingerprint;
  final int count;
  final String sourceKind;
  final String ownerKind;
  final String ownerId;
  final String reason;
  final List<String> evidence;
  final String removalCondition;

  String get identityKey => jsonEncode(<String, Object?>{
    'path': path,
    'directiveKind': directiveKind.wireName,
    'diagnostic': diagnostic,
    'targetFingerprint': targetFingerprint.toJson(),
    'count': count,
  });

  @override
  int compareTo(SuppressionInventoryEntry other) =>
      identityKey.compareTo(other.identityKey);
}

class SuppressionInventory {
  SuppressionInventory._(this.entries);

  factory SuppressionInventory.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    final json = _strictObject(decoded, 'inventory', const <String>{
      'schemaVersion',
      'policy',
      'entries',
    });
    if (json['schemaVersion'] != 1) {
      throw const FormatException('schemaVersion must be exactly 1.');
    }
    if (json['policy'] != 'production-unused-suppressions') {
      throw const FormatException('Unknown suppression inventory policy.');
    }
    final rawEntries = json['entries'];
    if (rawEntries is! List) {
      throw const FormatException('entries must be a JSON array.');
    }
    final entries =
        rawEntries
            .map(SuppressionInventoryEntry.fromJson)
            .toList(growable: false)
          ..sort();
    final identities = <String>{};
    for (final entry in entries) {
      if (!identities.add(entry.identityKey)) {
        throw FormatException(
          'Duplicate inventory identity: ${entry.identityKey}',
        );
      }
    }
    return SuppressionInventory._(List.unmodifiable(entries));
  }

  static SuppressionInventory loadSync(File file) =>
      SuppressionInventory.fromJsonString(file.readAsStringSync());

  final List<SuppressionInventoryEntry> entries;
}

class GitVisiblePaths {
  const GitVisiblePaths({required this.visible, required this.deleted});

  final List<String> visible;
  final List<String> deleted;
}

typedef GitPathLister = GitVisiblePaths Function(String repoRoot);

void validateGitEnvironment(Map<String, String> environment) {
  const repositoryRedirects = <String>{
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
                repositoryRedirects.contains(key) ||
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

class SuppressionCheckResult {
  SuppressionCheckResult({
    required List<SuppressionOccurrence> occurrences,
    required List<SuppressionIssue> issues,
    required List<String> packageRoots,
  }) : occurrences = List.unmodifiable(occurrences..sort()),
       issues = List.unmodifiable(issues..sort()),
       packageRoots = List.unmodifiable(packageRoots..sort());

  final List<SuppressionOccurrence> occurrences;
  final List<SuppressionIssue> issues;
  final List<String> packageRoots;

  bool get trustworthy =>
      !issues.any((issue) => issue.kind == SuppressionIssueKind.untrusted);
  bool get hasPolicyDrift =>
      issues.any((issue) => issue.kind == SuppressionIssueKind.policy);

  int get exitCode {
    if (!trustworthy) return 2;
    if (hasPolicyDrift) return 1;
    return 0;
  }
}

class AnalyzerSuppressionRatchet {
  AnalyzerSuppressionRatchet({
    required String repoRoot,
    required this.inventory,
    GitPathLister? gitPathLister,
    String? sdkPath,
  }) : repoRoot = p.normalize(p.absolute(repoRoot)),
       _gitPathLister = gitPathLister ?? listGitVisiblePaths,
       _sdkPath = sdkPath;

  final String repoRoot;
  final SuppressionInventory inventory;
  final GitPathLister _gitPathLister;
  final String? _sdkPath;
  late final String _resolvedRepoRoot = Directory(
    repoRoot,
  ).resolveSymbolicLinksSync();

  static GitVisiblePaths listGitVisiblePaths(
    String repoRoot, {
    Map<String, String>? environment,
  }) {
    final gitEnvironment = environment ?? Platform.environment;
    validateGitEnvironment(gitEnvironment);

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
      final line = utf8.decode(bytes.sublist(0, end));
      if (line.isEmpty ||
          bytes.sublist(0, end).contains(0) ||
          line.contains('\n') ||
          line.contains('\r')) {
        throw FormatException(
          'Git emitted an invalid single-line response for '
          '${arguments.join(' ')}.',
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
        'Git directory does not match the repository anchor: '
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
    final reportedIndexFile = File(absoluteReportedIndex);
    final resolvedReportedIndex = reportedIndexFile.existsSync()
        ? reportedIndexFile.resolveSymbolicLinksSync()
        : p.join(
            Directory(
              p.dirname(absoluteReportedIndex),
            ).resolveSymbolicLinksSync(),
            p.basename(absoluteReportedIndex),
          );
    final expectedIndex = p.normalize(
      p.absolute(p.join(reportedGitDirectory, 'index')),
    );
    if (!p.equals(resolvedReportedIndex, expectedIndex)) {
      throw FormatException(
        'Git index does not match the repository Git directory: '
        '$resolvedReportedIndex',
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

  Future<SuppressionCheckResult> check() async {
    final issues = <SuppressionIssue>[];
    final occurrences = <SuppressionOccurrence>[];
    final packageRoots = <String>[];
    AnalysisContextCollection? collection;

    try {
      final paths = _gitPathLister(repoRoot);
      final deleted = paths.deleted.map(_normalizeGitPath).toSet();
      final visible = paths.visible
          .map(_normalizeGitPath)
          .where((path) => !deleted.contains(path))
          .toSet();
      for (final deletedPubspec in deleted.where(
        (path) => path == 'pubspec.yaml' || path.endsWith('/pubspec.yaml'),
      )) {
        final packageRoot = p.posix.dirname(deletedPubspec);
        final libPath = packageRoot == '.' ? 'lib' : '$packageRoot/lib';
        final libPrefix = '$libPath/';
        if (visible.any(
          (path) => path.startsWith(libPrefix) && path.endsWith('.dart'),
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
      if (!File(
        p.join(repoRoot, '.dart_tool', 'package_config.json'),
      ).existsSync()) {
        throw const FileSystemException(
          'Missing resolved .dart_tool/package_config.json.',
        );
      }

      for (final pubspecPath in visible.where(
        (path) => path == 'pubspec.yaml' || path.endsWith('/pubspec.yaml'),
      )) {
        final pubspec = File(_repoPath(pubspecPath));
        _requireContainedEntity(pubspec, pubspecPath);
        final packageRoot = p.posix.dirname(pubspecPath);
        final normalizedRoot = packageRoot == '.' ? '' : packageRoot;
        final libRelative = normalizedRoot.isEmpty
            ? 'lib'
            : '$normalizedRoot/lib';
        final libDirectory = Directory(_repoPath(libRelative));
        if (!libDirectory.existsSync()) continue;
        _requireContainedEntity(libDirectory, libRelative);
        final yaml = loadYamlNode(pubspec.readAsStringSync());
        if (yaml is! YamlMap ||
            yaml['name'] is! String ||
            (yaml['name'] as String).trim().isEmpty) {
          throw FormatException(
            'Package pubspec has no non-empty name: $pubspecPath',
          );
        }
        packageRoots.add(normalizedRoot);
      }
      packageRoots.sort();
      if (!packageRoots.contains('')) {
        throw const FormatException('The root package has no sibling lib/.');
      }

      final productionPaths = <String>[];
      for (final path in visible.where((path) => path.endsWith('.dart'))) {
        final owningRoots = packageRoots.where((root) {
          final prefix = root.isEmpty ? 'lib/' : '$root/lib/';
          return path.startsWith(prefix);
        }).toList();
        if (owningRoots.isEmpty) continue;
        final file = File(_repoPath(path));
        if (!file.existsSync()) {
          throw FileSystemException(
            'Git-visible production source disappeared during scan.',
            path,
          );
        }
        _requireContainedEntity(file, path);
        productionPaths.add(path);
      }
      productionPaths.sort();

      final includedPaths =
          packageRoots
              .map(
                (root) => p.normalize(
                  p.absolute(
                    _repoPath(root.isEmpty ? 'lib' : p.posix.join(root, 'lib')),
                  ),
                ),
              )
              .toSet()
              .toList()
            ..sort();
      collection = AnalysisContextCollection(
        includedPaths: includedPaths,
        sdkPath: _sdkPath ?? _discoverDartSdkPath(),
      );
      final validatedOptions = <String>{};

      for (final relativePath in productionPaths) {
        final absolutePath = p.normalize(p.absolute(_repoPath(relativePath)));
        final applicable = collection.contexts
            .where(
              (context) => context.contextRoot.includedPaths.any(
                (included) =>
                    absolutePath == included ||
                    p.isWithin(included, absolutePath),
              ),
            )
            .toList();
        if (applicable.isEmpty) {
          throw StateError('No analyzer context owns $relativePath.');
        }
        final analyzed = applicable
            .where((context) => context.contextRoot.isAnalyzed(absolutePath))
            .toList();
        if (analyzed.isEmpty) {
          issues.add(
            SuppressionIssue(
              kind: SuppressionIssueKind.policy,
              code: 'production-source-excluded',
              path: relativePath,
              message: 'Production source is excluded from analyzer contexts.',
            ),
          );
          for (final context in applicable) {
            _validateOptionsGraph(
              context,
              validatedOptions,
              sourcePath: absolutePath,
            );
          }
          continue;
        }

        final context = analyzed.first;
        _validateOptionsGraph(
          context,
          validatedOptions,
          sourcePath: absolutePath,
        );
        final parsed = context.currentSession.getParsedUnit(absolutePath);
        if (parsed is! ParsedUnitResult) {
          throw StateError(
            'Analyzer did not return ParsedUnitResult for $relativePath.',
          );
        }
        if (parsed.diagnostics.isNotEmpty) {
          throw FormatException(
            'Parse diagnostics in $relativePath: '
            '${parsed.diagnostics.map((entry) => entry.toString()).join('; ')}',
          );
        }
        for (final processor in parsed.analysisOptions.errorProcessors) {
          if (processor.code.toLowerCase().startsWith('unused_') &&
              processor.severity == null) {
            issues.add(
              SuppressionIssue(
                kind: SuppressionIssueKind.policy,
                code: 'unused-diagnostic-globally-ignored',
                path: relativePath,
                message:
                    '${processor.code.toLowerCase()} is hidden by effective '
                    'analyzer options.',
              ),
            );
          }
        }
        occurrences.addAll(_scanUnit(relativePath, parsed, issues));
      }

      _compareInventory(occurrences, issues);
    } on Object catch (error) {
      issues.add(
        SuppressionIssue(
          kind: SuppressionIssueKind.untrusted,
          code: 'untrusted-scan',
          message: '$error',
        ),
      );
    } finally {
      if (collection != null) await collection.dispose();
    }

    return SuppressionCheckResult(
      occurrences: occurrences,
      issues: issues,
      packageRoots: packageRoots,
    );
  }

  void _compareInventory(
    List<SuppressionOccurrence> occurrences,
    List<SuppressionIssue> issues,
  ) {
    final actual = <String, List<SuppressionOccurrence>>{};
    for (final occurrence in occurrences) {
      actual.putIfAbsent(occurrence.identityKey, () => []).add(occurrence);
    }
    final expected = <String, SuppressionInventoryEntry>{
      for (final entry in inventory.entries) entry.identityKey: entry,
    };
    for (final entry in actual.entries) {
      if (entry.value.length != 1 || !expected.containsKey(entry.key)) {
        final occurrence = entry.value.first;
        issues.add(
          SuppressionIssue(
            kind: SuppressionIssueKind.policy,
            code: entry.value.length == 1
                ? 'unexpected-suppression'
                : 'duplicate-suppression',
            path: occurrence.path,
            line: occurrence.line,
            message: occurrence.identityKey,
          ),
        );
      }
    }
    for (final entry in inventory.entries) {
      final matches = actual[entry.identityKey];
      if (matches == null || matches.length != 1) {
        issues.add(
          SuppressionIssue(
            kind: SuppressionIssueKind.policy,
            code: 'stale-inventory-entry',
            path: entry.path,
            message: entry.identityKey,
          ),
        );
      }
    }
  }

  List<SuppressionOccurrence> _scanUnit(
    String relativePath,
    ParsedUnitResult parsed,
    List<SuppressionIssue> issues,
  ) {
    final visitor = _FingerprintVisitor(parsed);
    parsed.unit.accept(visitor);
    final candidates = visitor.candidates;
    final occurrences = <SuppressionOccurrence>[];
    final seenCommentOffsets = <int>{};

    Token? token = parsed.unit.beginToken;
    while (token != null) {
      CommentToken? comment = token.precedingComments;
      while (comment != null) {
        if (seenCommentOffsets.add(comment.offset)) {
          final directive = _parseDirective(comment.lexeme);
          if (directive != null) {
            final commentLine = parsed.lineInfo
                .getLocation(comment.offset)
                .lineNumber;
            final lineStart = comment.offset == 0
                ? 0
                : parsed.content.lastIndexOf('\n', comment.offset - 1) + 1;
            final hasCodeBefore = parsed.content
                .substring(lineStart, comment.offset)
                .trim()
                .isNotEmpty;
            final targetLine = hasCodeBefore ? commentLine : commentLine + 1;

            for (final code in directive.codes) {
              final normalized = code.toLowerCase();
              final broadWarning = normalized == 'type=warning';
              final diagnostic = normalized.contains('/')
                  ? normalized.substring(normalized.lastIndexOf('/') + 1)
                  : normalized;
              if (!broadWarning && !diagnostic.startsWith('unused_')) {
                continue;
              }
              if (directive.kind == SuppressionDirectiveKind.ignoreForFile ||
                  broadWarning) {
                issues.add(
                  SuppressionIssue(
                    kind: SuppressionIssueKind.policy,
                    code: broadWarning
                        ? 'broad-warning-suppression'
                        : 'file-wide-unused-suppression',
                    path: relativePath,
                    line: commentLine,
                    message:
                        'Only exact single-target unused_* suppressions may '
                        'be inventoried.',
                  ),
                );
                continue;
              }
              final targets = candidates
                  .where((candidate) => candidate.line == targetLine)
                  .toList();
              if (targets.length != 1) {
                issues.add(
                  SuppressionIssue(
                    kind: SuppressionIssueKind.policy,
                    code: targets.isEmpty
                        ? 'targetless-suppression'
                        : 'ambiguous-suppression-target',
                    path: relativePath,
                    line: commentLine,
                    message:
                        'Expected one AST target on line $targetLine, found '
                        '${targets.length}.',
                  ),
                );
                continue;
              }
              occurrences.add(
                SuppressionOccurrence(
                  path: relativePath,
                  directiveKind: directive.kind,
                  diagnostic: diagnostic,
                  targetFingerprint: targets.single.fingerprint,
                  count: 1,
                  line: commentLine,
                ),
              );
            }
          }
        }
        final next = comment.next;
        comment = next is CommentToken ? next : null;
      }
      if (token.isEof) break;
      token = token.next;
    }
    return occurrences;
  }

  void _validateOptionsGraph(
    AnalysisContext context,
    Set<String> validated, {
    required String sourcePath,
  }) {
    final optionsPath =
        _nearestAnalysisOptions(sourcePath) ??
        context.contextRoot.optionsFile?.path;
    if (optionsPath == null) return;
    final contextIdentity =
        context.contextRoot.packagesFile?.path ?? context.contextRoot.root.path;

    void visit(String rawPath, Set<String> active) {
      final file = File(p.normalize(p.absolute(rawPath)));
      if (!file.existsSync()) {
        throw FileSystemException('Missing analysis-options include.', rawPath);
      }
      final canonical = file.resolveSymbolicLinksSync();
      if (active.contains(canonical)) {
        throw FormatException('Analysis-options include cycle at $canonical.');
      }
      final validationKey = '$contextIdentity::$canonical';
      if (validated.contains(validationKey)) return;
      active.add(canonical);

      final document = loadYamlNode(
        file.readAsStringSync(),
        sourceUrl: file.uri,
      );
      if (document is! YamlMap) {
        throw FormatException('Analysis options must be a map: $canonical');
      }
      final analyzer = document['analyzer'];
      if (analyzer != null && analyzer is! YamlMap) {
        throw FormatException('analyzer must be a map: $canonical');
      }
      if (analyzer is YamlMap) {
        final errors = analyzer['errors'];
        if (errors != null && errors is! YamlMap) {
          throw FormatException('analyzer.errors must be a map: $canonical');
        }
        if (errors is YamlMap) {
          for (final entry in errors.nodes.entries) {
            if (entry.key.value is! String ||
                (entry.value.value is! String && entry.value.value is! bool)) {
              throw FormatException(
                'analyzer.errors must map strings to strings/bools: '
                '$canonical',
              );
            }
          }
        }
        final exclude = analyzer['exclude'];
        if (exclude != null &&
            (exclude is! YamlList ||
                exclude.nodes.any((node) => node.value is! String))) {
          throw FormatException(
            'analyzer.exclude must be a string list: $canonical',
          );
        }
      }

      final include = document['include'];
      final includes = switch (include) {
        null => const <String>[],
        String value => <String>[value],
        YamlList list when list.nodes.every((node) => node.value is String) =>
          list.nodes.map((node) => node.value! as String).toList(),
        _ => throw FormatException(
          'include must be a string or string list: $canonical',
        ),
      };
      for (final includeText in includes) {
        final uri = Uri.parse(includeText);
        String? includePath;
        if (uri.scheme == 'package') {
          includePath = context.currentSession.uriConverter.uriToPath(uri);
        } else if (!uri.hasScheme) {
          includePath = file.uri.resolveUri(uri).toFilePath();
        } else if (uri.scheme == 'file') {
          includePath = uri.toFilePath();
        }
        if (includePath == null) {
          throw FormatException(
            'Unresolvable analysis-options include $includeText in $canonical',
          );
        }
        visit(includePath, active);
      }
      active.remove(canonical);
      validated.add(validationKey);
    }

    visit(optionsPath, <String>{});
  }

  String? _nearestAnalysisOptions(String sourcePath) {
    var directory = File(sourcePath).parent;
    while (true) {
      final candidate = File(p.join(directory.path, 'analysis_options.yaml'));
      if (candidate.existsSync()) return candidate.path;
      if (p.equals(directory.path, repoRoot)) return null;
      final parent = directory.parent;
      if (p.equals(parent.path, directory.path) ||
          (!p.equals(parent.path, repoRoot) &&
              !p.isWithin(repoRoot, parent.path))) {
        return null;
      }
      directory = parent;
    }
  }

  String _repoPath(String relativePath) =>
      p.joinAll(<String>[repoRoot, ...p.posix.split(relativePath)]);

  String _normalizeGitPath(String rawPath) {
    if (rawPath.isEmpty ||
        rawPath.contains('\\') ||
        p.posix.isAbsolute(rawPath) ||
        rawPath.split('/').contains('..')) {
      throw FormatException('Unsafe Git path: $rawPath');
    }
    final normalized = p.posix.normalize(rawPath);
    if (normalized == '.' || normalized.startsWith('../')) {
      throw FormatException('Unsafe Git path: $rawPath');
    }
    return normalized;
  }

  void _requireContainedEntity(FileSystemEntity entity, String displayPath) {
    final absolute = p.normalize(p.absolute(entity.path));
    if (absolute != repoRoot && !p.isWithin(repoRoot, absolute)) {
      throw FormatException('Path escapes repository: $displayPath');
    }
    final resolved = entity.resolveSymbolicLinksSync();
    if (resolved != _resolvedRepoRoot &&
        !p.isWithin(_resolvedRepoRoot, resolved)) {
      throw FormatException('Symlink escapes repository: $displayPath');
    }
  }
}

String _resolveGitDirectory(String repoRoot) {
  final markerPath = p.join(repoRoot, '.git');
  final markerDirectory = Directory(markerPath);
  if (markerDirectory.existsSync()) {
    return markerDirectory.resolveSymbolicLinksSync();
  }

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
  final referenced = marker.substring(prefix.length);
  final gitDirectory = Directory(
    p.isAbsolute(referenced)
        ? referenced
        : p.normalize(p.join(repoRoot, referenced)),
  );
  if (!gitDirectory.existsSync()) {
    throw FileSystemException(
      'The .git gitdir target does not exist.',
      gitDirectory.path,
    );
  }
  return gitDirectory.resolveSymbolicLinksSync();
}

class _ParsedDirective {
  const _ParsedDirective({required this.kind, required this.codes});

  final SuppressionDirectiveKind kind;
  final List<String> codes;
}

_ParsedDirective? _parseDirective(String lexeme) {
  final match = RegExp(
    r'^//+[ \t]*(ignore_for_file|ignore)[ \t]*:[ \t]*(.*)$',
  ).firstMatch(lexeme);
  if (match == null) return null;
  final kind = match.group(1) == 'ignore_for_file'
      ? SuppressionDirectiveKind.ignoreForFile
      : SuppressionDirectiveKind.ignore;
  final codes = <String>[];
  for (final rawSegment in match.group(2)!.split(',')) {
    final segment = rawSegment.trimLeft();
    final token = RegExp(
      r'^(type[ \t]*=[ \t]*[A-Za-z]+|'
      r'[A-Za-z][A-Za-z0-9_]*(?:/[A-Za-z][A-Za-z0-9_]*)?)',
      caseSensitive: false,
    ).firstMatch(segment);
    if (token == null) break;
    codes.add(token.group(1)!.replaceAll(RegExp(r'[ \t]+'), ''));
  }
  return _ParsedDirective(kind: kind, codes: codes);
}

class _TargetCandidate {
  const _TargetCandidate({required this.line, required this.fingerprint});

  final int line;
  final TargetFingerprint fingerprint;
}

class _FingerprintVisitor extends RecursiveAstVisitor<void> {
  _FingerprintVisitor(this.result);

  final ParsedUnitResult result;
  final List<_TargetCandidate> candidates = <_TargetCandidate>[];

  @override
  void visitImportDirective(ImportDirective node) {
    final uri = node.uri.stringValue;
    if (uri != null) {
      final combinators = <String>[];
      for (final combinator in node.combinators) {
        if (combinator is ShowCombinator) {
          combinators.add(
            'show:${combinator.shownNames.map((name) => name.name).join(',')}',
          );
        } else if (combinator is HideCombinator) {
          combinators.add(
            'hide:${combinator.hiddenNames.map((name) => name.name).join(',')}',
          );
        }
      }
      _add(
        node.importKeyword.offset,
        TargetFingerprint(
          kind: 'import',
          ownerChain: const <String>[],
          name: uri,
          signature:
              'uri=$uri;prefix=${node.prefix?.name ?? ''};'
              'deferred=${node.deferredKeyword != null};'
              'combinators=[${combinators.join('|')}]',
        ),
      );
    }
    super.visitImportDirective(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final end =
        node.functionExpression.parameters?.endToken ??
        node.propertyKeyword ??
        node.name;
    _add(
      node.name.offset,
      TargetFingerprint(
        kind: 'function',
        ownerChain: _ownerChain(node),
        name: node.name.lexeme,
        signature: _tokenSignature(node.firstTokenAfterCommentAndMetadata, end),
      ),
    );
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final end = node.parameters?.endToken ?? node.name;
    _add(
      node.name.offset,
      TargetFingerprint(
        kind: 'method',
        ownerChain: _ownerChain(node),
        name: node.name.lexeme,
        signature: _tokenSignature(node.firstTokenAfterCommentAndMetadata, end),
      ),
    );
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final anchor = node.name ?? node.returnType.endToken;
    _add(
      anchor.offset,
      TargetFingerprint(
        kind: 'constructor',
        ownerChain: _ownerChain(node),
        name: node.name?.lexeme ?? '<unnamed>',
        signature: _tokenSignature(
          node.firstTokenAfterCommentAndMetadata,
          node.parameters.endToken,
        ),
      ),
    );
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _addNamedType(
      node: node,
      anchor: node.name,
      end: node.leftBracket.previous ?? node.name,
      kind: 'class',
    );
    super.visitClassDeclaration(node);
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    _addNamedType(
      node: node,
      anchor: node.name,
      end: node.leftBracket.previous ?? node.name,
      kind: 'mixin',
    );
    super.visitMixinDeclaration(node);
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    _addNamedType(
      node: node,
      anchor: node.name,
      end: node.leftBracket.previous ?? node.name,
      kind: 'enum',
    );
    super.visitEnumDeclaration(node);
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    final name = node.name;
    if (name != null) {
      _addNamedType(
        node: node,
        anchor: name,
        end: node.leftBracket.previous ?? name,
        kind: 'extension',
      );
    }
    super.visitExtensionDeclaration(node);
  }

  @override
  void visitExtensionTypeDeclaration(ExtensionTypeDeclaration node) {
    _addNamedType(
      node: node,
      anchor: node.name,
      end: node.leftBracket.previous ?? node.name,
      kind: 'extension-type',
    );
    super.visitExtensionTypeDeclaration(node);
  }

  @override
  void visitGenericTypeAlias(GenericTypeAlias node) {
    _addNamedType(
      node: node,
      anchor: node.name,
      end: node.endToken,
      kind: 'type-alias',
    );
    super.visitGenericTypeAlias(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final declarationList = node.parent;
    final start = declarationList is VariableDeclarationList
        ? declarationList.beginToken
        : node.name;
    _add(
      node.name.offset,
      TargetFingerprint(
        kind: 'variable',
        ownerChain: _ownerChain(node),
        name: node.name.lexeme,
        signature: _tokenSignature(start, node.name),
      ),
    );
    super.visitVariableDeclaration(node);
  }

  void _addNamedType({
    required AnnotatedNode node,
    required Token anchor,
    required Token end,
    required String kind,
  }) {
    _add(
      anchor.offset,
      TargetFingerprint(
        kind: kind,
        ownerChain: _ownerChain(node),
        name: anchor.lexeme,
        signature: _tokenSignature(node.firstTokenAfterCommentAndMetadata, end),
      ),
    );
  }

  void _add(int offset, TargetFingerprint fingerprint) {
    candidates.add(
      _TargetCandidate(
        line: result.lineInfo.getLocation(offset).lineNumber,
        fingerprint: fingerprint,
      ),
    );
  }
}

List<String> _ownerChain(AstNode node) {
  final owners = <String>[];
  AstNode? current = node.parent;
  while (current != null) {
    if (current is ClassDeclaration) {
      owners.add('class:${current.name.lexeme}');
    } else if (current is MixinDeclaration) {
      owners.add('mixin:${current.name.lexeme}');
    } else if (current is EnumDeclaration) {
      owners.add('enum:${current.name.lexeme}');
    } else if (current is ExtensionDeclaration) {
      final headerEnd =
          current.leftBracket.previous ??
          current.name ??
          current.extensionKeyword;
      owners.add(
        'extension:${current.name?.lexeme ?? '<unnamed>'}:'
        '${_tokenSignature(current.firstTokenAfterCommentAndMetadata, headerEnd)}',
      );
    } else if (current is ExtensionTypeDeclaration) {
      owners.add('extension-type:${current.name.lexeme}');
    } else if (current is MethodDeclaration) {
      owners.add('method:${current.name.lexeme}');
    } else if (current is FunctionDeclaration) {
      owners.add('function:${current.name.lexeme}');
    }
    current = current.parent;
  }
  return owners.reversed.toList(growable: false);
}

String _tokenSignature(Token start, Token end) {
  final lexemes = <String>[];
  Token? token = start;
  while (token != null) {
    lexemes.add(token.lexeme);
    if (identical(token, end)) return lexemes.join(' ');
    if (token.isEof) break;
    token = token.next;
  }
  throw StateError('Could not construct a stable token signature.');
}

bool _isSafeExactPath(String path) {
  if (path.isEmpty ||
      path.contains('*') ||
      path.contains('?') ||
      path.contains('[') ||
      path.contains('\\') ||
      p.posix.isAbsolute(path)) {
    return false;
  }
  final normalized = p.posix.normalize(path);
  return normalized == path &&
      normalized != '.' &&
      normalized != '..' &&
      !normalized.startsWith('../');
}

bool _containsWildcard(String value) =>
    value.contains('*') || value.contains('?');

String _discoverDartSdkPath() {
  final candidates = <String>[];
  final dartSdk = Platform.environment['DART_SDK'];
  if (dartSdk != null && dartSdk.isNotEmpty) candidates.add(dartSdk);
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null && flutterRoot.isNotEmpty) {
    candidates.add(p.join(flutterRoot, 'bin', 'cache', 'dart-sdk'));
  }

  final executable = File(
    Platform.resolvedExecutable,
  ).resolveSymbolicLinksSync();
  candidates.add(p.dirname(p.dirname(executable)));
  Directory? current = File(executable).parent;
  while (current != null) {
    candidates
      ..add(p.join(current.path, 'bin', 'cache', 'dart-sdk'))
      ..add(p.join(current.path, 'cache', 'dart-sdk'));
    final parent = current.parent;
    if (parent.path == current.path) break;
    current = parent;
  }

  for (final candidate in candidates) {
    final normalized = p.normalize(p.absolute(candidate));
    if (File(p.join(normalized, 'lib', 'libraries.json')).existsSync()) {
      return normalized;
    }
  }
  throw StateError('Unable to locate the resolved Dart SDK.');
}

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

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value;
}

List<String> _requiredStringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List ||
      value.any((entry) => entry is! String || entry.trim().isEmpty)) {
    throw FormatException('$key must be a list of non-empty strings.');
  }
  return value.cast<String>();
}

Future<int> runAnalyzerSuppressionRatchetCli(List<String> arguments) async {
  if (arguments.length != 1 || arguments.single != 'check') {
    stderr.writeln(
      'Usage: dart tool/analyzer_guard/'
      'analyzer_suppression_ratchet.dart check',
    );
    return 2;
  }
  try {
    final script = File.fromUri(Platform.script).absolute;
    final repoRoot = script.parent.parent.parent.path;
    final inventory = SuppressionInventory.loadSync(
      File(
        p.join(
          repoRoot,
          'tool',
          'analyzer_guard',
          'production_unused_suppressions.json',
        ),
      ),
    );
    final result = await AnalyzerSuppressionRatchet(
      repoRoot: repoRoot,
      inventory: inventory,
    ).check();
    stdout.writeln(
      'Production unused-suppression ratchet: '
      '${result.occurrences.length} reviewed occurrence(s), '
      '${result.packageRoots.length} package root(s).',
    );
    for (final issue in result.issues) {
      stderr.writeln('${issue.kind.name}: $issue');
    }
    return result.exitCode;
  } on Object catch (error) {
    stderr.writeln('Analyzer suppression ratchet failed: $error');
    return 2;
  }
}

Future<void> main(List<String> arguments) async {
  exitCode = await runAnalyzerSuppressionRatchetCli(arguments);
}
