import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import 'package:yaml/yaml.dart';

/// Exit-independent severity for inventory findings.
enum InventoryIssueKind { drift, fatal }

/// A deterministic, machine-readable inventory finding.
class InventoryIssue implements Comparable<InventoryIssue> {
  const InventoryIssue({
    required this.kind,
    required this.code,
    required this.message,
    this.path,
  });

  final InventoryIssueKind kind;
  final String code;
  final String message;
  final String? path;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'code': code,
    if (path != null) 'path': path,
    'message': message,
  };

  @override
  int compareTo(InventoryIssue other) {
    final byKind = kind.name.compareTo(other.kind.name);
    if (byKind != 0) return byKind;
    final byPath = (path ?? '').compareTo(other.path ?? '');
    if (byPath != 0) return byPath;
    final byCode = code.compareTo(other.code);
    if (byCode != 0) return byCode;
    return message.compareTo(other.message);
  }
}

enum RuntimeRootOrigin {
  main('main'),
  manual('manual'),
  tooling('tooling'),
  testIntegration('test/integration');

  const RuntimeRootOrigin(this.wireName);
  final String wireName;
}

enum ReachabilityBucket {
  mainReachable('main-reachable'),
  manualRootReachable('manual-root-reachable'),
  toolingReachable('tooling-reachable'),
  testIntegrationReachable('test/integration-reachable'),
  unrooted('unrooted');

  const ReachabilityBucket(this.wireName);
  final String wireName;
}

enum RuntimeRootKind {
  appEntrypoint('app-entrypoint'),
  manualEntrypoint('manual-entrypoint'),
  vmCallback('vm-callback'),
  conventionCallback('convention-callback'),
  nativeRegistration('native-registration'),
  generated('generated'),
  headlessPlugin('headless-plugin'),
  tooling('tooling'),
  compatibility('compatibility'),
  resource('resource');

  const RuntimeRootKind(this.wireName);
  final String wireName;

  static RuntimeRootKind parse(String value) => values.firstWhere(
    (entry) => entry.wireName == value,
    orElse: () => throw FormatException('Unknown root kind: $value'),
  );
}

enum ReviewDisposition {
  explainedRoot('explained-root'),
  candidate('candidate'),
  deferredReview('deferred-review'),
  retainedUnresolved('retained-unresolved');

  const ReviewDisposition(this.wireName);
  final String wireName;

  static ReviewDisposition parse(String value) => values.firstWhere(
    (entry) => entry.wireName == value,
    orElse: () => throw FormatException('Unknown disposition: $value'),
  );
}

class EvidenceSpec {
  const EvidenceSpec({required this.kind, required this.fields});

  factory EvidenceSpec.fromJson(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('Evidence must be a JSON object.');
    }
    final kind = _requiredString(value, 'kind');
    final fields = <String, String>{};
    for (final entry in value.entries) {
      if (entry.key == 'kind') continue;
      if (entry.value is! String) {
        throw FormatException(
          'Evidence ${entry.key} must be a string for kind $kind.',
        );
      }
      fields[entry.key] = entry.value! as String;
    }
    return EvidenceSpec(kind: kind, fields: Map.unmodifiable(fields));
  }

  final String kind;
  final Map<String, String> fields;

  String? operator [](String key) => fields[key];

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    ...Map<String, String>.fromEntries(
      fields.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    ),
  };
}

class ManualRootSpec {
  const ManualRootSpec({
    required this.path,
    required this.owner,
    required this.reason,
    required this.condition,
  });

  factory ManualRootSpec.fromJson(Object? value) {
    final json = _object(value, 'manual root');
    return ManualRootSpec(
      path: _requiredString(json, 'path'),
      owner: _requiredString(json, 'owner'),
      reason: _requiredString(json, 'reason'),
      condition: _requiredString(json, 'condition'),
    );
  }

  final String path;
  final String owner;
  final String reason;
  final String condition;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'owner': owner,
    'reason': reason,
    'condition': condition,
  };
}

class ExternalEntrypointSpec {
  const ExternalEntrypointSpec({
    required this.path,
    required this.owner,
    required this.reason,
    required this.condition,
    required this.seedsTooling,
    required this.evidence,
  });

  factory ExternalEntrypointSpec.fromJson(Object? value) {
    final json = _object(value, 'external entrypoint');
    return ExternalEntrypointSpec(
      path: _requiredString(json, 'path'),
      owner: _requiredString(json, 'owner'),
      reason: _requiredString(json, 'reason'),
      condition: _requiredString(json, 'condition'),
      seedsTooling: _requiredBool(json, 'seedsTooling'),
      evidence: _list(
        json['evidence'],
        'external entrypoint evidence',
      ).map(EvidenceSpec.fromJson).toList(growable: false),
    );
  }

  final String path;
  final String owner;
  final String reason;
  final String condition;
  final bool seedsTooling;
  final List<EvidenceSpec> evidence;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'owner': owner,
    'reason': reason,
    'condition': condition,
    'seedsTooling': seedsTooling,
    'evidence': evidence.map((entry) => entry.toJson()).toList(),
  };
}

class DeclarationSpec {
  const DeclarationSpec({
    required this.path,
    required this.rootKinds,
    required this.disposition,
    required this.owner,
    required this.reason,
    required this.condition,
    required this.evidence,
  });

  factory DeclarationSpec.fromJson(Object? value) {
    final json = _object(value, 'declaration');
    final rootKindNames = _stringList(json['rootKinds'], 'rootKinds');
    if (rootKindNames.toSet().length != rootKindNames.length) {
      throw const FormatException('rootKinds must not contain duplicates.');
    }
    return DeclarationSpec(
      path: _requiredString(json, 'path'),
      rootKinds: rootKindNames.map(RuntimeRootKind.parse).toSet(),
      disposition: ReviewDisposition.parse(
        _requiredString(json, 'disposition'),
      ),
      owner: _requiredString(json, 'owner'),
      reason: _requiredString(json, 'reason'),
      condition: _requiredString(json, 'condition'),
      evidence: _list(
        json['evidence'],
        'declaration evidence',
      ).map(EvidenceSpec.fromJson).toList(growable: false),
    );
  }

  final String path;
  final Set<RuntimeRootKind> rootKinds;
  final ReviewDisposition disposition;
  final String owner;
  final String reason;
  final String condition;
  final List<EvidenceSpec> evidence;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'rootKinds': rootKinds.map((entry) => entry.wireName).toList()..sort(),
    'disposition': disposition.wireName,
    'owner': owner,
    'reason': reason,
    'condition': condition,
    'evidence': evidence.map((entry) => entry.toJson()).toList(),
  };
}

class RestrictedRootSpec {
  const RestrictedRootSpec({
    required this.id,
    required this.path,
    required this.rootKind,
    required this.owner,
    required this.reason,
    required this.condition,
    required this.evidence,
  });

  factory RestrictedRootSpec.fromJson(Object? value) {
    final json = _object(value, 'restricted root');
    return RestrictedRootSpec(
      id: _requiredString(json, 'id'),
      path: _requiredString(json, 'path'),
      rootKind: RuntimeRootKind.parse(_requiredString(json, 'rootKind')),
      owner: _requiredString(json, 'owner'),
      reason: _requiredString(json, 'reason'),
      condition: _requiredString(json, 'condition'),
      evidence: _list(
        json['evidence'],
        'restricted root evidence',
      ).map(EvidenceSpec.fromJson).toList(growable: false),
    );
  }

  final String id;
  final String path;
  final RuntimeRootKind rootKind;
  final String owner;
  final String reason;
  final String condition;
  final List<EvidenceSpec> evidence;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'path': path,
    'rootKind': rootKind.wireName,
    'owner': owner,
    'reason': reason,
    'condition': condition,
    'evidence': evidence.map((entry) => entry.toJson()).toList(),
  };
}

class RestrictedRootRequirement {
  const RestrictedRootRequirement({required this.id, required this.rootKind});

  factory RestrictedRootRequirement.fromJson(Object? value) {
    final json = _object(value, 'required restricted root');
    return RestrictedRootRequirement(
      id: _requiredString(json, 'id'),
      rootKind: RuntimeRootKind.parse(_requiredString(json, 'rootKind')),
    );
  }

  final String id;
  final RuntimeRootKind rootKind;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'rootKind': rootKind.wireName,
  };
}

class RuntimeRootsManifest {
  const RuntimeRootsManifest({
    required this.schemaVersion,
    required this.manualRoots,
    required this.externalEntrypoints,
    required this.declarations,
    required this.requiredRestrictedRoots,
    required this.restrictedRoots,
  });

  factory RuntimeRootsManifest.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    final json = _object(decoded, 'manifest');
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion is! int) {
      throw const FormatException('schemaVersion must be an integer.');
    }
    return RuntimeRootsManifest(
      schemaVersion: schemaVersion,
      manualRoots: _list(
        json['manualRoots'],
        'manualRoots',
      ).map(ManualRootSpec.fromJson).toList(growable: false),
      externalEntrypoints: _list(
        json['externalEntrypoints'],
        'externalEntrypoints',
      ).map(ExternalEntrypointSpec.fromJson).toList(growable: false),
      declarations: _list(
        json['declarations'],
        'declarations',
      ).map(DeclarationSpec.fromJson).toList(growable: false),
      requiredRestrictedRoots: _list(
        json['requiredRestrictedRoots'],
        'requiredRestrictedRoots',
      ).map(RestrictedRootRequirement.fromJson).toList(growable: false),
      restrictedRoots: _list(
        json['restrictedRoots'],
        'restrictedRoots',
      ).map(RestrictedRootSpec.fromJson).toList(growable: false),
    );
  }

  static RuntimeRootsManifest loadSync(File file) =>
      RuntimeRootsManifest.fromJsonString(file.readAsStringSync());

  final int schemaVersion;
  final List<ManualRootSpec> manualRoots;
  final List<ExternalEntrypointSpec> externalEntrypoints;
  final List<DeclarationSpec> declarations;
  final List<RestrictedRootRequirement> requiredRestrictedRoots;
  final List<RestrictedRootSpec> restrictedRoots;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'manualRoots': manualRoots.map((entry) => entry.toJson()).toList(),
    'externalEntrypoints': externalEntrypoints
        .map((entry) => entry.toJson())
        .toList(),
    'declarations': declarations.map((entry) => entry.toJson()).toList(),
    'requiredRestrictedRoots': requiredRestrictedRoots
        .map((entry) => entry.toJson())
        .toList(),
    'restrictedRoots': restrictedRoots.map((entry) => entry.toJson()).toList(),
  };
}

class DartFileInventory {
  const DartFileInventory({
    required this.path,
    required this.origins,
    required this.bucket,
    required this.incomingEdges,
    required this.rootKinds,
    required this.disposition,
    required this.owner,
    required this.reason,
    required this.condition,
  });

  final String path;
  final Set<RuntimeRootOrigin> origins;
  final ReachabilityBucket bucket;
  final List<String> incomingEdges;
  final Set<RuntimeRootKind> rootKinds;
  final ReviewDisposition? disposition;
  final String? owner;
  final String? reason;
  final String? condition;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'origins': origins.map((entry) => entry.wireName).toList()..sort(),
    'bucket': bucket.wireName,
    'incomingEdges': incomingEdges,
    'rootKinds': rootKinds.map((entry) => entry.wireName).toList()..sort(),
    if (disposition != null) 'disposition': disposition!.wireName,
    if (owner != null) 'owner': owner,
    if (reason != null) 'reason': reason,
    if (condition != null) 'condition': condition,
  };
}

class ExternalEntrypointInventory {
  const ExternalEntrypointInventory({
    required this.path,
    required this.invoked,
    required this.reachesLib,
    required this.declared,
  });

  final String path;
  final bool invoked;
  final bool reachesLib;
  final bool declared;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'invoked': invoked,
    'reachesLib': reachesLib,
    'declared': declared,
  };
}

class RestrictedRootInventory {
  const RestrictedRootInventory({
    required this.id,
    required this.path,
    required this.rootKind,
    required this.validated,
  });

  final String id;
  final String path;
  final RuntimeRootKind rootKind;
  final bool validated;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'path': path,
    'rootKind': rootKind.wireName,
    'validated': validated,
  };
}

class RuntimeRootInventoryResult {
  RuntimeRootInventoryResult({
    required this.repoRoot,
    required this.packageName,
    required this.files,
    required this.externalEntrypoints,
    required this.restrictedRoots,
    required List<InventoryIssue> issues,
    required this.descendantPackageRoots,
  }) : issues = List<InventoryIssue>.unmodifiable(issues..sort());

  final String repoRoot;
  final String packageName;
  final List<DartFileInventory> files;
  final List<ExternalEntrypointInventory> externalEntrypoints;
  final List<RestrictedRootInventory> restrictedRoots;
  final List<InventoryIssue> issues;
  final List<String> descendantPackageRoots;

  bool get trustworthy =>
      !issues.any((issue) => issue.kind == InventoryIssueKind.fatal);
  bool get hasDrift =>
      issues.any((issue) => issue.kind == InventoryIssueKind.drift);

  int exitCodeFor({required bool check}) {
    if (!trustworthy) return 2;
    if (check && hasDrift) return 1;
    return 0;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'trustworthy': trustworthy,
    'drift': hasDrift,
    'packageName': packageName,
    'descendantPackageRoots': descendantPackageRoots,
    'files': files.map((entry) => entry.toJson()).toList(),
    'externalEntrypoints': externalEntrypoints
        .map((entry) => entry.toJson())
        .toList(),
    'restrictedRoots': restrictedRoots.map((entry) => entry.toJson()).toList(),
    'issues': issues.map((entry) => entry.toJson()).toList(),
  };

  String renderJson() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';

  String renderText() {
    final buffer = StringBuffer()
      ..writeln('Runtime-root inventory')
      ..writeln('trustworthy: $trustworthy')
      ..writeln('drift: $hasDrift')
      ..writeln('package: $packageName')
      ..writeln('files: ${files.length}');
    for (final file in files) {
      buffer.writeln(
        '${file.bucket.wireName}\t${file.path}\t'
        '${file.disposition?.wireName ?? 'unreviewed'}',
      );
    }
    if (externalEntrypoints.isNotEmpty) {
      buffer.writeln('external-entrypoints:');
      for (final entry in externalEntrypoints) {
        buffer.writeln(
          '${entry.path}\tinvoked=${entry.invoked}\t'
          'reachesLib=${entry.reachesLib}\tdeclared=${entry.declared}',
        );
      }
    }
    if (restrictedRoots.isNotEmpty) {
      buffer.writeln('restricted-roots:');
      for (final entry in restrictedRoots) {
        buffer.writeln(
          '${entry.id}\t${entry.rootKind.wireName}\t${entry.path}\t'
          'validated=${entry.validated}',
        );
      }
    }
    if (issues.isNotEmpty) {
      buffer.writeln('issues:');
      for (final issue in issues) {
        buffer.writeln(
          '${issue.kind.name}\t${issue.code}\t'
          '${issue.path == null ? '' : '${issue.path}\t'}${issue.message}',
        );
      }
    }
    return buffer.toString();
  }
}

typedef GitPathLister = List<String> Function(String repoRoot);

class RuntimeRootInventory {
  RuntimeRootInventory({
    required String repoRoot,
    required this.manifest,
    GitPathLister? gitPathLister,
    GitPathLister? gitDeletedPathLister,
  }) : repoRoot = p.normalize(p.absolute(repoRoot)),
       _gitPathLister = gitPathLister ?? listGitVisiblePaths,
       _gitDeletedPathLister =
           gitDeletedPathLister ??
           (gitPathLister == null
               ? listGitDeletedPaths
               : _emptyInjectedDeletedPaths);

  final String repoRoot;
  final RuntimeRootsManifest manifest;
  final GitPathLister _gitPathLister;
  final GitPathLister _gitDeletedPathLister;

  static const Set<String> allowedManualRootPaths = <String>{
    'lib/smoke_test_main.dart',
    'lib/smoke_test_messages.dart',
    'lib/smoke_test_restore.dart',
  };

  static List<String> listGitVisiblePaths(String repoRoot) {
    return _runGitPathCommand(repoRoot, <String>[
      'ls-files',
      '-z',
      '--cached',
      '--others',
      '--exclude-standard',
    ], label: 'git ls-files');
  }

  static List<String> listGitDeletedPaths(String repoRoot) {
    return _runGitPathCommand(repoRoot, <String>[
      'ls-files',
      '-z',
      '--deleted',
    ], label: 'git ls-files --deleted');
  }

  static List<String> _emptyInjectedDeletedPaths(String _) => const <String>[];

  static List<String> _runGitPathCommand(
    String repoRoot,
    List<String> arguments, {
    required String label,
  }) {
    final result = Process.runSync(
      'git',
      <String>['-C', repoRoot, ...arguments],
      stdoutEncoding: null,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      throw FileSystemException(
        '$label failed (${result.exitCode}): ${result.stderr}',
        repoRoot,
      );
    }
    final bytes = result.stdout as List<int>;
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
      throw FormatException('$label emitted a non-NUL tail.');
    }
    return paths;
  }

  RuntimeRootInventoryResult scan() {
    final issues = <InventoryIssue>[];
    List<String> enumerated;
    List<String> deleted;
    try {
      enumerated = _gitPathLister(repoRoot);
      deleted = _gitDeletedPathLister(repoRoot);
    } on Object catch (error) {
      return RuntimeRootInventoryResult(
        repoRoot: repoRoot,
        packageName: '',
        files: const <DartFileInventory>[],
        externalEntrypoints: const <ExternalEntrypointInventory>[],
        restrictedRoots: const <RestrictedRootInventory>[],
        issues: <InventoryIssue>[
          InventoryIssue(
            kind: InventoryIssueKind.fatal,
            code: 'git-enumeration-failed',
            message: '$error',
          ),
        ],
        descendantPackageRoots: const <String>[],
      );
    }

    final existingPaths = <String>{};
    for (final rawPath in enumerated) {
      final normalized = _normalizeEnumeratedPath(rawPath, issues);
      if (normalized == null) continue;
      final entityPath = _repoPath(normalized);
      if (FileSystemEntity.typeSync(entityPath, followLinks: false) !=
          FileSystemEntityType.notFound) {
        existingPaths.add(normalized);
      }
    }
    final deletedPaths = <String>{};
    for (final rawPath in deleted) {
      final normalized = _normalizeEnumeratedPath(rawPath, issues);
      if (normalized != null) deletedPaths.add(normalized);
    }

    if (!existingPaths.contains('pubspec.yaml') ||
        !File(p.join(repoRoot, 'pubspec.yaml')).existsSync()) {
      issues.add(
        const InventoryIssue(
          kind: InventoryIssueKind.fatal,
          code: 'missing-root-pubspec',
          path: 'pubspec.yaml',
          message: 'The root pubspec is a required scan anchor.',
        ),
      );
    }
    if (!existingPaths.contains('lib/main.dart') ||
        !File(p.join(repoRoot, 'lib/main.dart')).existsSync()) {
      issues.add(
        const InventoryIssue(
          kind: InventoryIssueKind.fatal,
          code: 'missing-main-entrypoint',
          path: 'lib/main.dart',
          message: 'lib/main.dart is a required scan anchor.',
        ),
      );
    }

    final packageName = _readPackageName(issues);
    final descendantPackageRoots = _discoverDescendantPackageRoots(
      existingPaths,
      issues,
    );

    bool insideDescendantPackage(String path) => descendantPackageRoots.any(
      (root) => path == root || path.startsWith('$root/'),
    );

    for (final path in deletedPaths) {
      if (insideDescendantPackage(path) ||
          !_isRuntimeInventoryTrackedPath(path)) {
        continue;
      }
      issues.add(
        InventoryIssue(
          kind: InventoryIssueKind.drift,
          code: 'tracked-path-deleted',
          path: path,
          message:
              'A tracked runtime-inventory path is deleted or renamed in the working tree.',
        ),
      );
    }

    final dartPaths =
        existingPaths
            .where((path) => path.endsWith('.dart'))
            .where((path) => !insideDescendantPackage(path))
            .toList()
          ..sort();

    final units = <String, _ParsedDartUnit>{};
    for (final path in dartPaths) {
      final file = File(_repoPath(path));
      try {
        final parsed = parseString(
          content: file.readAsStringSync(),
          path: file.path,
          throwIfDiagnostics: false,
        );
        if (parsed.errors.isNotEmpty) {
          issues.add(
            InventoryIssue(
              kind: InventoryIssueKind.fatal,
              code: 'dart-parse-failed',
              path: path,
              message: parsed.errors
                  .map((error) => error.message)
                  .toSet()
                  .join('; '),
            ),
          );
          continue;
        }
        units[path] = _ParsedDartUnit.fromParseResult(path, parsed);
      } on Object catch (error) {
        issues.add(
          InventoryIssue(
            kind: InventoryIssueKind.fatal,
            code: 'dart-parse-failed',
            path: path,
            message: '$error',
          ),
        );
      }
    }

    final edges = <String, Set<String>>{
      for (final path in dartPaths) path: <String>{},
    };
    for (final entry in units.entries) {
      for (final uri in entry.value.directiveUris) {
        final target = _resolveDirective(
          sourcePath: entry.key,
          uri: uri,
          packageName: packageName,
          dartPaths: dartPaths.toSet(),
          issues: issues,
        );
        if (target != null) edges[entry.key]!.add(target);
      }
    }

    _validateManifestShape(
      existingPaths: existingPaths,
      dartPaths: dartPaths.toSet(),
      issues: issues,
    );

    final validManualRoots = <String>{};
    for (final manual in manifest.manualRoots) {
      if (_validateManualRoot(manual, units, issues)) {
        validManualRoots.add(manual.path);
      }
    }

    final validExternalEntrypoints = <String, ExternalEntrypointSpec>{};
    for (final entry in manifest.externalEntrypoints) {
      var valid = true;
      if (!units.containsKey(entry.path) || !units[entry.path]!.hasMain) {
        issues.add(
          InventoryIssue(
            kind: InventoryIssueKind.drift,
            code: 'external-entrypoint-not-main',
            path: entry.path,
            message:
                'Declared external entrypoint has no AST top-level main().',
          ),
        );
        valid = false;
      }
      if (entry.seedsTooling && entry.evidence.isEmpty) {
        issues.add(
          InventoryIssue(
            kind: InventoryIssueKind.drift,
            code: 'tool-root-missing-invocation',
            path: entry.path,
            message: 'A tooling origin requires invocation evidence.',
          ),
        );
        valid = false;
      }
      if (entry.seedsTooling &&
          !_hasToolInvocationEvidence(entry.path, entry.evidence)) {
        issues.add(
          InventoryIssue(
            kind: InventoryIssueKind.drift,
            code: 'tool-root-incompatible-evidence',
            path: entry.path,
            message:
                'A tooling origin requires a command/structured invocation bound to the exact entrypoint.',
          ),
        );
        valid = false;
      }
      for (final evidence in entry.evidence) {
        if (!_validateEvidence(
          evidence,
          units: units,
          edges: edges,
          existingPaths: existingPaths,
          issues: issues,
          subjectPath: entry.path,
        )) {
          valid = false;
        }
      }
      if (valid) validExternalEntrypoints[entry.path] = entry;
    }

    final conventionRoots = dartPaths.where(_isConventionEntrypoint).toSet();
    final toolingRoots = validExternalEntrypoints.values
        .where((entry) => entry.seedsTooling)
        .map((entry) => entry.path)
        .toSet();

    final mainClosure = _closure(<String>{'lib/main.dart'}, edges);
    final manualClosures = <String, Set<String>>{
      for (final root in validManualRoots)
        root: _closure(<String>{root}, edges),
    };
    final toolingClosures = <String, Set<String>>{
      for (final root in toolingRoots) root: _closure(<String>{root}, edges),
    };
    final conventionClosure = _closure(conventionRoots, edges);

    final incoming = <String, List<String>>{
      for (final path in dartPaths) path: <String>[],
    };
    for (final entry in edges.entries) {
      for (final target in entry.value) {
        incoming[target]?.add(entry.key);
      }
    }
    for (final paths in incoming.values) {
      paths.sort();
    }

    final declarationByPath = <String, DeclarationSpec>{};
    for (final declaration in manifest.declarations) {
      if (declarationByPath.containsKey(declaration.path)) continue;
      declarationByPath[declaration.path] = declaration;
    }

    final files = <DartFileInventory>[];
    final libPaths = dartPaths
        .where((path) => path.startsWith('lib/') && path.endsWith('.dart'))
        .toList();
    for (final path in libPaths) {
      final origins = <RuntimeRootOrigin>{};
      if (mainClosure.contains(path)) origins.add(RuntimeRootOrigin.main);
      if (manualClosures.values.any((closure) => closure.contains(path))) {
        origins.add(RuntimeRootOrigin.manual);
      }
      if (toolingClosures.values.any((closure) => closure.contains(path))) {
        origins.add(RuntimeRootOrigin.tooling);
      }
      if (conventionClosure.contains(path)) {
        origins.add(RuntimeRootOrigin.testIntegration);
      }
      final bucket = _bucketFor(origins);
      final declaration = declarationByPath[path];
      final effectiveDisposition =
          declaration?.disposition ??
          (bucket == ReachabilityBucket.mainReachable
              ? ReviewDisposition.explainedRoot
              : null);
      files.add(
        DartFileInventory(
          path: path,
          origins: Set.unmodifiable(origins),
          bucket: bucket,
          incomingEdges: List.unmodifiable(incoming[path] ?? const <String>[]),
          rootKinds: Set.unmodifiable(
            declaration?.rootKinds ?? const <RuntimeRootKind>{},
          ),
          disposition: effectiveDisposition,
          owner: declaration?.owner,
          reason: declaration?.reason,
          condition: declaration?.condition,
        ),
      );
    }
    files.sort((a, b) => a.path.compareTo(b.path));

    final fileByPath = <String, DartFileInventory>{
      for (final file in files) file.path: file,
    };

    for (final declaration in manifest.declarations) {
      final file = fileByPath[declaration.path];
      if (file == null) {
        issues.add(
          InventoryIssue(
            kind: InventoryIssueKind.drift,
            code: 'stale-declaration',
            path: declaration.path,
            message: 'Declared app source is absent from the current scan.',
          ),
        );
        continue;
      }
      var evidenceValid = true;
      for (final evidence in declaration.evidence) {
        if (evidence.kind == 'computed-origin') {
          final expected = evidence['origin'];
          if (expected == null ||
              !file.origins.any((origin) => origin.wireName == expected)) {
            issues.add(
              InventoryIssue(
                kind: InventoryIssueKind.drift,
                code: 'stale-computed-origin',
                path: declaration.path,
                message: 'Expected computed origin is not currently present.',
              ),
            );
            evidenceValid = false;
          }
          continue;
        }
        if (!_validateEvidence(
          evidence,
          units: units,
          edges: edges,
          existingPaths: existingPaths,
          issues: issues,
          subjectPath: declaration.path,
        )) {
          evidenceValid = false;
        }
      }
      final rootEvidenceCompatible = declaration.rootKinds.every(
        (rootKind) => _validateRootEvidenceCompatibility(
          subjectPath: declaration.path,
          rootKind: rootKind,
          evidence: declaration.evidence,
          issues: issues,
        ),
      );
      _validateDeclarationAgainstComputed(
        declaration,
        file,
        evidenceValid && rootEvidenceCompatible,
        issues,
      );
    }

    for (final file in files) {
      if (file.bucket != ReachabilityBucket.mainReachable &&
          !declarationByPath.containsKey(file.path)) {
        issues.add(
          InventoryIssue(
            kind: InventoryIssueKind.drift,
            code: 'unreviewed-non-main-source',
            path: file.path,
            message:
                'Every non-main-reachable app source needs an exact reviewed declaration.',
          ),
        );
      }
    }

    final detectedVmCallbacks = <String>{};
    for (final entry in units.entries) {
      for (final callback in entry.value.vmEntrypoints) {
        detectedVmCallbacks.add('${entry.key}::$callback');
      }
    }

    final restrictedById = <String, RestrictedRootSpec>{
      for (final entry in manifest.restrictedRoots) entry.id: entry,
    };
    final requiredRestrictedById = <String, RestrictedRootRequirement>{
      for (final entry in manifest.requiredRestrictedRoots) entry.id: entry,
    };
    for (final requirement in manifest.requiredRestrictedRoots) {
      final record = restrictedById[requirement.id];
      if (record == null) {
        issues.add(
          InventoryIssue(
            kind: InventoryIssueKind.drift,
            code: 'missing-required-restricted-root',
            path: requirement.id,
            message:
                'Required ${requirement.rootKind.wireName} restricted-root record is absent.',
          ),
        );
      } else if (record.rootKind != requirement.rootKind) {
        issues.add(
          InventoryIssue(
            kind: InventoryIssueKind.drift,
            code: 'restricted-root-kind-mismatch',
            path: record.path,
            message:
                '${record.id} must remain tagged ${requirement.rootKind.wireName}.',
          ),
        );
      }
    }

    final restrictedRootInventory = <RestrictedRootInventory>[];
    final protectedVmCallbacks = <String>{};
    for (final restricted in manifest.restrictedRoots) {
      var valid = true;
      final requirement = requiredRestrictedById[restricted.id];
      if (requirement == null) {
        issues.add(
          InventoryIssue(
            kind: InventoryIssueKind.drift,
            code: 'unratcheted-restricted-root',
            path: restricted.path,
            message:
                'Every restricted-root record must have a required id/kind contract.',
          ),
        );
        valid = false;
      } else if (requirement.rootKind != restricted.rootKind) {
        valid = false;
      }
      for (final evidence in restricted.evidence) {
        if (!_validateEvidence(
          evidence,
          units: units,
          edges: edges,
          existingPaths: existingPaths,
          issues: issues,
          subjectPath: restricted.path,
        )) {
          valid = false;
        }
      }
      if (!_validateRootEvidenceCompatibility(
        subjectPath: restricted.path,
        rootKind: restricted.rootKind,
        evidence: restricted.evidence,
        issues: issues,
      )) {
        valid = false;
      }
      if (valid && restricted.rootKind == RuntimeRootKind.vmCallback) {
        for (final evidence in restricted.evidence.where(
          (entry) => entry.kind == 'dart-annotation',
        )) {
          final symbol = evidence['symbol'];
          if (symbol != null) {
            protectedVmCallbacks.add('${restricted.path}::$symbol');
          }
        }
      }
      restrictedRootInventory.add(
        RestrictedRootInventory(
          id: restricted.id,
          path: restricted.path,
          rootKind: restricted.rootKind,
          validated: valid,
        ),
      );
    }
    restrictedRootInventory.sort((a, b) => a.id.compareTo(b.id));
    for (final callback in detectedVmCallbacks.difference(
      protectedVmCallbacks,
    )) {
      final separator = callback.indexOf('::');
      issues.add(
        InventoryIssue(
          kind: InventoryIssueKind.drift,
          code: 'unreviewed-vm-entrypoint',
          path: callback.substring(0, separator),
          message:
              'VM entrypoint ${callback.substring(separator + 2)} lacks validated restricted-root evidence.',
        ),
      );
    }

    final externalCandidates = <ExternalEntrypointInventory>[];
    for (final entry in units.entries) {
      final path = entry.key;
      if (!entry.value.hasMain ||
          path == 'lib/main.dart' ||
          validManualRoots.contains(path) ||
          conventionRoots.contains(path)) {
        continue;
      }
      final reachesLib = _closure(<String>{
        path,
      }, edges).any((target) => target.startsWith('lib/'));
      final declaration = validExternalEntrypoints[path];
      final referenced = manifest.externalEntrypoints.any(
        (candidate) => candidate.path == path,
      );
      if (!reachesLib && !referenced) continue;
      externalCandidates.add(
        ExternalEntrypointInventory(
          path: path,
          invoked: declaration?.seedsTooling ?? false,
          reachesLib: reachesLib,
          declared: declaration != null,
        ),
      );
      if (declaration == null) {
        issues.add(
          InventoryIssue(
            kind: InventoryIssueKind.drift,
            code: 'unreviewed-external-entrypoint',
            path: path,
            message:
                'A non-convention top-level main reaching app source needs an exact reviewed record.',
          ),
        );
      }
    }
    externalCandidates.sort((a, b) => a.path.compareTo(b.path));

    return RuntimeRootInventoryResult(
      repoRoot: repoRoot,
      packageName: packageName,
      files: List.unmodifiable(files),
      externalEntrypoints: List.unmodifiable(externalCandidates),
      restrictedRoots: List.unmodifiable(restrictedRootInventory),
      issues: issues,
      descendantPackageRoots: descendantPackageRoots,
    );
  }

  String _readPackageName(List<InventoryIssue> issues) {
    try {
      final source = File(p.join(repoRoot, 'pubspec.yaml')).readAsStringSync();
      final yaml = loadYaml(source);
      if (yaml is! YamlMap || yaml['name'] is! String) {
        throw const FormatException('Root pubspec has no string name.');
      }
      final name = (yaml['name'] as String).trim();
      if (!_isValidPackageName(name)) {
        throw const FormatException('Package name is empty or malformed.');
      }
      return name;
    } on Object catch (error) {
      issues.add(
        InventoryIssue(
          kind: InventoryIssueKind.fatal,
          code: 'invalid-root-pubspec',
          path: 'pubspec.yaml',
          message: '$error',
        ),
      );
      return '';
    }
  }

  List<String> _discoverDescendantPackageRoots(
    Set<String> existingPaths,
    List<InventoryIssue> issues,
  ) {
    final roots = <String>[];
    final pubspecPaths =
        existingPaths
            .where(
              (path) =>
                  path != 'pubspec.yaml' && path.endsWith('/pubspec.yaml'),
            )
            .toList()
          ..sort();
    for (final pubspecPath in pubspecPaths) {
      final root = p.posix.dirname(pubspecPath);
      try {
        final decoded = loadYaml(
          File(_repoPath(pubspecPath)).readAsStringSync(),
        );
        if (decoded is! YamlMap ||
            decoded['name'] is! String ||
            !_isValidPackageName((decoded['name'] as String).trim())) {
          throw const FormatException(
            'Descendant pubspec has no valid package name.',
          );
        }
        final hasLibraryRoot = existingPaths.any(
          (path) => path.startsWith('$root/lib/') && path.endsWith('.dart'),
        );
        if (hasLibraryRoot) roots.add(root);
      } on Object catch (error) {
        issues.add(
          InventoryIssue(
            kind: InventoryIssueKind.fatal,
            code: 'invalid-descendant-pubspec',
            path: pubspecPath,
            message:
                'A malformed descendant pubspec cannot hide its Dart tree: $error',
          ),
        );
      }
    }
    return roots;
  }

  static bool _isValidPackageName(String value) =>
      RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value);

  static bool _isRuntimeInventoryTrackedPath(String path) {
    if (path == 'pubspec.yaml' || path == 'lib/main.dart') return true;
    if (path.endsWith('/pubspec.yaml')) return true;
    return path.startsWith('lib/') && path.endsWith('.dart');
  }

  static String? _normalizeEnumeratedPath(
    String rawPath,
    List<InventoryIssue> issues,
  ) {
    final slashed = rawPath.replaceAll('\\', '/');
    if (slashed.isEmpty ||
        p.posix.isAbsolute(slashed) ||
        slashed.split('/').contains('..')) {
      issues.add(
        InventoryIssue(
          kind: InventoryIssueKind.fatal,
          code: 'unsafe-enumerated-path',
          path: rawPath,
          message: 'Git emitted a path outside the repository contract.',
        ),
      );
      return null;
    }
    return p.posix.normalize(slashed);
  }

  String? _resolveDirective({
    required String sourcePath,
    required String uri,
    required String packageName,
    required Set<String> dartPaths,
    required List<InventoryIssue> issues,
  }) {
    if (uri.startsWith('dart:')) return null;
    String? target;
    final parsed = Uri.tryParse(uri);
    if (parsed == null ||
        parsed.hasQuery ||
        parsed.hasFragment ||
        parsed.scheme == 'file' ||
        uri.startsWith('/')) {
      _fatalDirective(issues, sourcePath, uri, 'unsafe or malformed URI');
      return null;
    }
    if (parsed.hasScheme) {
      if (parsed.scheme != 'package') {
        _fatalDirective(issues, sourcePath, uri, 'unsupported URI scheme');
        return null;
      }
      final segments = parsed.pathSegments;
      if (segments.isEmpty || segments.first != packageName) return null;
      if (segments.length == 1) {
        _fatalDirective(issues, sourcePath, uri, 'empty self-package target');
        return null;
      }
      target = p.posix.join('lib', p.posix.joinAll(segments.skip(1)));
    } else {
      target = p.posix.normalize(
        p.posix.join(p.posix.dirname(sourcePath), parsed.path),
      );
      if (target == '..' || target.startsWith('../')) {
        _fatalDirective(issues, sourcePath, uri, 'target escapes repository');
        return null;
      }
    }
    if (!dartPaths.contains(target)) {
      _fatalDirective(
        issues,
        sourcePath,
        uri,
        'unresolved or wrong-case root-package target $target',
      );
      return null;
    }
    return target;
  }

  static void _fatalDirective(
    List<InventoryIssue> issues,
    String sourcePath,
    String uri,
    String reason,
  ) {
    issues.add(
      InventoryIssue(
        kind: InventoryIssueKind.fatal,
        code: 'untrustworthy-directive',
        path: sourcePath,
        message: '$uri: $reason',
      ),
    );
  }

  void _validateManifestShape({
    required Set<String> existingPaths,
    required Set<String> dartPaths,
    required List<InventoryIssue> issues,
  }) {
    if (manifest.schemaVersion != 1) {
      issues.add(
        InventoryIssue(
          kind: InventoryIssueKind.fatal,
          code: 'unsupported-manifest-schema',
          message: 'Expected schemaVersion 1, got ${manifest.schemaVersion}.',
        ),
      );
    }
    _validateUniquePaths(
      manifest.manualRoots.map((entry) => entry.path),
      'manual-root',
      issues,
    );
    _validateUniquePaths(
      manifest.externalEntrypoints.map((entry) => entry.path),
      'external-entrypoint',
      issues,
    );
    _validateUniquePaths(
      manifest.declarations.map((entry) => entry.path),
      'declaration',
      issues,
    );
    _validateUniquePaths(
      manifest.restrictedRoots.map((entry) => entry.id),
      'restricted-root-id',
      issues,
    );
    _validateUniquePaths(
      manifest.requiredRestrictedRoots.map((entry) => entry.id),
      'required-restricted-root-id',
      issues,
    );
    for (final path in <String>[
      ...manifest.manualRoots.map((entry) => entry.path),
      ...manifest.externalEntrypoints.map((entry) => entry.path),
      ...manifest.declarations.map((entry) => entry.path),
      ...manifest.restrictedRoots.map((entry) => entry.path),
    ]) {
      if (!_isSafeExactPath(path)) {
        issues.add(
          InventoryIssue(
            kind: InventoryIssueKind.fatal,
            code: 'unsafe-manifest-path',
            path: path,
            message: 'Manifest paths must be exact repository-relative paths.',
          ),
        );
      }
    }
    for (final manual in manifest.manualRoots) {
      if (!allowedManualRootPaths.contains(manual.path)) {
        issues.add(
          InventoryIssue(
            kind: InventoryIssueKind.drift,
            code: 'manual-policy-outside-closed-set',
            path: manual.path,
            message: 'manual-policy is limited to the three smoke targets.',
          ),
        );
      }
    }
    for (final declaration in manifest.declarations) {
      if (!declaration.path.startsWith('lib/') ||
          !declaration.path.endsWith('.dart')) {
        issues.add(
          InventoryIssue(
            kind: InventoryIssueKind.fatal,
            code: 'invalid-declaration-target',
            path: declaration.path,
            message: 'App declarations must target exact lib/**/*.dart files.',
          ),
        );
      }
      if (declaration.owner.trim().isEmpty ||
          declaration.reason.trim().isEmpty ||
          declaration.condition.trim().isEmpty) {
        issues.add(
          InventoryIssue(
            kind: InventoryIssueKind.fatal,
            code: 'incomplete-declaration',
            path: declaration.path,
            message:
                'Owner, reason, and removal/revisit condition are required.',
          ),
        );
      }
      if (declaration.evidence.isEmpty &&
          declaration.disposition != ReviewDisposition.candidate &&
          declaration.disposition != ReviewDisposition.retainedUnresolved) {
        issues.add(
          InventoryIssue(
            kind: InventoryIssueKind.drift,
            code: 'declaration-missing-evidence',
            path: declaration.path,
            message: 'Reviewed declarations require current evidence.',
          ),
        );
      }
      if (declaration.disposition == ReviewDisposition.deferredReview &&
          declaration.condition.trim().isEmpty) {
        issues.add(
          InventoryIssue(
            kind: InventoryIssueKind.drift,
            code: 'ownerless-deferred-review',
            path: declaration.path,
            message: 'Deferred review requires a downstream owner/condition.',
          ),
        );
      }
    }
    for (final restricted in manifest.restrictedRoots) {
      if (!existingPaths.contains(restricted.path)) {
        issues.add(
          InventoryIssue(
            kind: InventoryIssueKind.drift,
            code: 'stale-restricted-root',
            path: restricted.path,
            message: 'Restricted-root source is absent.',
          ),
        );
      }
      if (restricted.evidence.isEmpty) {
        issues.add(
          InventoryIssue(
            kind: InventoryIssueKind.drift,
            code: 'restricted-root-missing-evidence',
            path: restricted.path,
            message: 'Restricted roots require typed structural evidence.',
          ),
        );
      }
    }
  }

  static void _validateUniquePaths(
    Iterable<String> values,
    String label,
    List<InventoryIssue> issues,
  ) {
    final seen = <String>{};
    for (final value in values) {
      if (!seen.add(value)) {
        issues.add(
          InventoryIssue(
            kind: InventoryIssueKind.fatal,
            code: 'duplicate-$label',
            path: value,
            message: 'Duplicate $label record.',
          ),
        );
      }
    }
  }

  static bool _isSafeExactPath(String path) {
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
        normalized != '..' &&
        !normalized.startsWith('../');
  }

  bool _validateManualRoot(
    ManualRootSpec manual,
    Map<String, _ParsedDartUnit> units,
    List<InventoryIssue> issues,
  ) {
    var valid = true;
    if (!allowedManualRootPaths.contains(manual.path)) valid = false;
    final unit = units[manual.path];
    if (unit == null || !unit.hasMain) valid = false;
    if (manual.owner.trim().isEmpty ||
        manual.reason.trim().isEmpty ||
        manual.condition.trim().isEmpty) {
      valid = false;
    }
    if (unit != null && !_hasLeadingManualCommand(unit.source, manual.path)) {
      valid = false;
    }
    if (!valid) {
      issues.add(
        InventoryIssue(
          kind: InventoryIssueKind.drift,
          code: 'invalid-manual-policy',
          path: manual.path,
          message:
              'Manual root requires allowed path, AST main(), matching documented target, owner, reason, and condition.',
        ),
      );
    }
    return valid;
  }

  static bool _hasLeadingManualCommand(String source, String targetPath) {
    final expected = RegExp(
      '^Run with:\\s*flutter run -t ${RegExp.escape(targetPath)}\\s*\$',
    );
    var inBlockComment = false;
    for (final rawLine in const LineSplitter().convert(source)) {
      var line = rawLine.trim();
      if (inBlockComment) {
        final end = line.indexOf('*/');
        final commentText = (end < 0 ? line : line.substring(0, end))
            .replaceFirst(RegExp(r'^\*\s?'), '')
            .trim();
        if (expected.hasMatch(commentText)) return true;
        if (end < 0) continue;
        inBlockComment = false;
        line = line.substring(end + 2).trim();
        if (line.isEmpty) continue;
        return false;
      }
      if (line.isEmpty) continue;
      if (line.startsWith('//')) {
        final commentText = line.replaceFirst(RegExp(r'^//+ ?'), '').trim();
        if (expected.hasMatch(commentText)) return true;
        continue;
      }
      if (line.startsWith('/*')) {
        inBlockComment = true;
        line = line.substring(2);
        final end = line.indexOf('*/');
        final commentText = (end < 0 ? line : line.substring(0, end))
            .replaceFirst(RegExp(r'^\*\s?'), '')
            .trim();
        if (expected.hasMatch(commentText)) return true;
        if (end < 0) continue;
        inBlockComment = false;
        if (line.substring(end + 2).trim().isEmpty) continue;
      }
      // The command must be in the leading documentation block. A later
      // comment, string, annotation, or arbitrary metadata cannot satisfy it.
      return false;
    }
    return false;
  }

  bool _validateEvidence(
    EvidenceSpec evidence, {
    required Map<String, _ParsedDartUnit> units,
    required Map<String, Set<String>> edges,
    required Set<String> existingPaths,
    required List<InventoryIssue> issues,
    required String subjectPath,
  }) {
    bool fail(String message) {
      issues.add(
        InventoryIssue(
          kind: InventoryIssueKind.drift,
          code: 'stale-${evidence.kind}',
          path: subjectPath,
          message: message,
        ),
      );
      return false;
    }

    final source = evidence['source'];
    if (evidence.kind != 'computed-origin' &&
        evidence.kind != 'manual-policy' &&
        (source == null || !_isSafeExactPath(source))) {
      return fail('Evidence requires an exact source path.');
    }
    if (source != null && !existingPaths.contains(source)) {
      return fail('Evidence source is absent: $source');
    }

    switch (evidence.kind) {
      case 'computed-origin':
        return true;
      case 'manual-policy':
        final target = evidence['target'] ?? subjectPath;
        final manual = manifest.manualRoots
            .where((entry) => entry.path == target)
            .firstOrNull;
        if (manual == null) return fail('Manual policy record is absent.');
        return _validateManualRoot(manual, units, <InventoryIssue>[]);
      case 'dart-main':
        return units[source]?.hasMain == true ||
            fail('No AST top-level main() at $source.');
      case 'dart-symbol':
        final symbol = evidence['symbol'];
        if (symbol == null) return fail('dart-symbol needs symbol.');
        return units[source]?.topLevelSymbols.contains(symbol) == true ||
            fail('No exact AST top-level symbol $symbol at $source.');
      case 'dart-directive':
        final target = evidence['target'];
        if (target == null) return fail('dart-directive needs target.');
        return edges[source]?.contains(target) == true ||
            fail('No exact Dart directive edge $source -> $target.');
      case 'dart-annotation':
        final symbol = evidence['symbol'];
        final annotation = evidence['annotation'];
        final value = evidence['value'];
        if (symbol == null || annotation == null || value == null) {
          return fail(
            'dart-annotation needs symbol, annotation, and value fields.',
          );
        }
        return units[source]?.annotations.any(
                  (entry) =>
                      entry.symbol == symbol &&
                      entry.name == annotation &&
                      entry.value == value,
                ) ==
                true ||
            fail('Exact Dart annotation relation is absent.');
      case 'dart-call-argument':
        final callee = evidence['callee'];
        final argument = evidence['argument'];
        if (callee == null || argument == null) {
          return fail('dart-call-argument needs callee and argument.');
        }
        return units[source]?.calls.any(
                  (call) =>
                      call.callee == callee &&
                      call.arguments.contains(argument),
                ) ==
                true ||
            fail('Exact Dart call/argument relation is absent.');
      case 'source-call-token':
        final callee = evidence['callee'];
        final argument = evidence['argument'];
        if (callee == null || argument == null) {
          return fail('source-call-token needs callee and argument.');
        }
        final content = File(_repoPath(source!)).readAsStringSync();
        return _hasCommentAwareCall(content, callee, argument) ||
            fail('Exact non-Dart call/token relation is absent.');
      case 'json-value':
        final keyPath = evidence['keyPath'];
        final value = evidence['value'];
        if (keyPath == null || value == null) {
          return fail('json-value needs keyPath and value.');
        }
        try {
          final decoded = jsonDecode(
            File(_repoPath(source!)).readAsStringSync(),
          );
          final selected = _selectStructuredValue(decoded, keyPath);
          return '$selected' == value ||
              fail('JSON key path does not have the expected value.');
        } on Object catch (error) {
          return fail('JSON evidence parse failed: $error');
        }
      case 'yaml-value':
        final keyPath = evidence['keyPath'];
        final value = evidence['value'];
        if (keyPath == null || value == null) {
          return fail('yaml-value needs keyPath and value.');
        }
        try {
          final decoded = loadYaml(File(_repoPath(source!)).readAsStringSync());
          final selected = _selectStructuredValue(decoded, keyPath);
          return '$selected' == value ||
              fail('YAML key path does not have the expected value.');
        } on Object catch (error) {
          return fail('YAML evidence parse failed: $error');
        }
      case 'xml-attribute':
        final element = evidence['element'];
        final attribute = evidence['attribute'];
        final value = evidence['value'];
        if (element == null || attribute == null || value == null) {
          return fail('xml-attribute needs element, attribute, and value.');
        }
        try {
          final document = XmlDocument.parse(
            File(_repoPath(source!)).readAsStringSync(),
          );
          return document
                  .findAllElements(element)
                  .any((node) => node.getAttribute(attribute) == value) ||
              fail('XML element/attribute/value relation is absent.');
        } on Object catch (error) {
          return fail('XML evidence parse failed: $error');
        }
      case 'plist-key-value':
        final key = evidence['key'];
        final value = evidence['value'];
        if (key == null || value == null) {
          return fail('plist-key-value needs key and value.');
        }
        try {
          final document = XmlDocument.parse(
            File(_repoPath(source!)).readAsStringSync(),
          );
          return _plistHasKeyValue(document, key, value) ||
              fail('Plist key/value relation is absent.');
        } on Object catch (error) {
          return fail('Plist evidence parse failed: $error');
        }
      case 'command-argument':
        final option = evidence['option'];
        final target = evidence['target'] ?? subjectPath;
        if (option == null) {
          return fail('command-argument needs option.');
        }
        final validCommand = source!.endsWith('.dart')
            ? units[source]?.commandArguments.any(
                    (entry) => entry.option == option && entry.target == target,
                  ) ==
                  true
            : _hasShellCommandArgument(
                File(_repoPath(source)).readAsStringSync(),
                option,
                target,
              );
        return validCommand ||
            fail('Command option does not select the exact target.');
      default:
        return fail('Unknown evidence kind: ${evidence.kind}');
    }
  }

  static Object? _selectStructuredValue(Object? root, String keyPath) {
    Object? current = root;
    for (final segment in keyPath.split('.')) {
      if (current is Map) {
        current = current[segment];
      } else if (current is List) {
        final index = int.parse(segment);
        current = current[index];
      } else {
        return null;
      }
    }
    return current;
  }

  String _repoPath(String relativePath) =>
      p.joinAll(<String>[repoRoot, ...p.posix.split(relativePath)]);

  static bool _plistHasKeyValue(
    XmlDocument document,
    String key,
    String value,
  ) {
    for (final keyElement in document.findAllElements('key')) {
      if (keyElement.innerText.trim() != key) continue;
      XmlElement? sibling;
      var node = keyElement.nextSibling;
      while (node != null) {
        if (node is XmlElement) {
          sibling = node;
          break;
        }
        node = node.nextSibling;
      }
      if (sibling?.innerText.trim() == value) return true;
    }
    return false;
  }

  static bool _hasCommentAwareCall(
    String source,
    String callee,
    String argument,
  ) {
    final masked = _maskLexicalNoise(source);
    final calleePattern = RegExp(
      '${RegExp.escape(callee)}\\s*\\(',
      multiLine: true,
    );
    for (final match in calleePattern.allMatches(masked.structure)) {
      var depth = 0;
      var end = match.end;
      for (; end < masked.structure.length; end++) {
        final char = masked.structure[end];
        if (char == '(') depth++;
        if (char == ')') {
          if (depth == 0) break;
          depth--;
        }
      }
      final call = masked.values.substring(
        match.start,
        end.clamp(0, masked.values.length),
      );
      if (_containsEvidenceArgument(call, argument)) return true;
    }
    return false;
  }

  static bool _hasShellCommandArgument(
    String source,
    String option,
    String target,
  ) {
    final masked = _maskLexicalNoise(source);
    final logicalSource = masked.values.replaceAll(RegExp(r'\\\r?\n'), ' ');
    final assignments = <String, String>{};
    final assignmentPattern = RegExp(
      r'''^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(?:"([^"]*)"|'([^']*)'|([^\s]+))\s*$''',
    );
    final lines = const LineSplitter().convert(logicalSource);
    for (final line in lines) {
      final match = assignmentPattern.firstMatch(line);
      if (match == null) continue;
      assignments[match.group(1)!] =
          match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
    }

    String resolve(String value) {
      final variable = RegExp(
        r'^\$(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))$',
      ).firstMatch(value);
      if (variable == null) return value;
      return assignments[variable.group(1) ?? variable.group(2)!] ?? value;
    }

    for (final line in lines) {
      if (assignmentPattern.hasMatch(line)) continue;
      final tokens = _shellTokens(line);
      if (tokens.isEmpty) continue;
      for (var index = 0; index < tokens.length; index++) {
        final token = tokens[index];
        if (token == option && index + 1 < tokens.length) {
          if (resolve(tokens[index + 1]) == target) return true;
        }
        if (token.startsWith('$option=') &&
            resolve(token.substring(option.length + 1)) == target) {
          return true;
        }
      }
    }
    return false;
  }

  static List<String> _shellTokens(String line) {
    final tokens = <String>[];
    final current = StringBuffer();
    String? quote;
    var index = 0;
    void flush() {
      if (current.isEmpty) return;
      tokens.add(current.toString());
      current.clear();
    }

    while (index < line.length) {
      final char = line[index];
      if (quote != null) {
        if (char == '\\' && quote == '"' && index + 1 < line.length) {
          current.write(line[index + 1]);
          index += 2;
          continue;
        }
        if (char == quote) {
          quote = null;
        } else {
          current.write(char);
        }
        index++;
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        index++;
        continue;
      }
      if (char.trim().isEmpty) {
        flush();
        index++;
        continue;
      }
      if (char == '\\' && index + 1 < line.length) {
        current.write(line[index + 1]);
        index += 2;
        continue;
      }
      current.write(char);
      index++;
    }
    flush();
    return tokens;
  }

  static bool _containsEvidenceArgument(String source, String argument) {
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_.]*$').hasMatch(argument)) {
      return source.contains(argument);
    }
    return RegExp(
      '(?<![A-Za-z0-9_])${RegExp.escape(argument)}(?![A-Za-z0-9_])',
    ).hasMatch(source);
  }

  static _MaskedLexicalSource _maskLexicalNoise(String source) {
    final structure = StringBuffer();
    final values = StringBuffer();
    var index = 0;
    String? quote;
    var blockComment = false;
    var lineComment = false;
    while (index < source.length) {
      final char = source[index];
      final next = index + 1 < source.length ? source[index + 1] : '';
      if (lineComment) {
        if (char == '\n') {
          lineComment = false;
          structure.write(char);
          values.write(char);
        } else {
          structure.write(' ');
          values.write(' ');
        }
        index++;
        continue;
      }
      if (blockComment) {
        if (char == '*' && next == '/') {
          structure.write('  ');
          values.write('  ');
          index += 2;
          blockComment = false;
        } else {
          final replacement = char == '\n' ? '\n' : ' ';
          structure.write(replacement);
          values.write(replacement);
          index++;
        }
        continue;
      }
      if (quote != null) {
        values.write(char);
        structure.write(char == '\n' ? '\n' : ' ');
        if (char == '\\' && index + 1 < source.length) {
          values.write(source[index + 1]);
          structure.write(' ');
          index += 2;
          continue;
        }
        if (char == quote) quote = null;
        index++;
        continue;
      }
      if (char == '/' && next == '/') {
        structure.write('  ');
        values.write('  ');
        index += 2;
        lineComment = true;
        continue;
      }
      if (char == '/' && next == '*') {
        structure.write('  ');
        values.write('  ');
        index += 2;
        blockComment = true;
        continue;
      }
      if (char == '#' && (index == 0 || source[index - 1].trim().isEmpty)) {
        structure.write(' ');
        values.write(' ');
        index++;
        lineComment = true;
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        structure.write(' ');
        values.write(char);
        index++;
        continue;
      }
      structure.write(char);
      values.write(char);
      index++;
    }
    return _MaskedLexicalSource(
      structure: structure.toString(),
      values: values.toString(),
    );
  }

  static bool _hasToolInvocationEvidence(
    String subjectPath,
    List<EvidenceSpec> evidence,
  ) => evidence.any(
    (entry) =>
        (entry.kind == 'command-argument' &&
            (entry['target'] ?? subjectPath) == subjectPath) ||
        ((entry.kind == 'json-value' || entry.kind == 'yaml-value') &&
            entry['value'] == subjectPath),
  );

  bool _validateRootEvidenceCompatibility({
    required String subjectPath,
    required RuntimeRootKind rootKind,
    required List<EvidenceSpec> evidence,
    required List<InventoryIssue> issues,
  }) {
    const allowedKinds = <RuntimeRootKind, Set<String>>{
      RuntimeRootKind.appEntrypoint: <String>{'dart-main', 'computed-origin'},
      RuntimeRootKind.manualEntrypoint: <String>{'manual-policy'},
      RuntimeRootKind.vmCallback: <String>{
        'dart-annotation',
        'dart-call-argument',
        'source-call-token',
      },
      RuntimeRootKind.conventionCallback: <String>{
        'dart-symbol',
        'dart-call-argument',
      },
      RuntimeRootKind.nativeRegistration: <String>{
        'xml-attribute',
        'plist-key-value',
        'source-call-token',
      },
      RuntimeRootKind.generated: <String>{
        'yaml-value',
        'json-value',
        'source-call-token',
        'dart-call-argument',
      },
      RuntimeRootKind.headlessPlugin: <String>{
        'yaml-value',
        'source-call-token',
      },
      RuntimeRootKind.tooling: <String>{
        'command-argument',
        'json-value',
        'yaml-value',
        'computed-origin',
      },
      RuntimeRootKind.compatibility: <String>{
        'dart-directive',
        'dart-call-argument',
        'json-value',
        'yaml-value',
        'source-call-token',
      },
      RuntimeRootKind.resource: <String>{
        'json-value',
        'yaml-value',
        'xml-attribute',
        'plist-key-value',
      },
    };

    void incompatible(String message) {
      issues.add(
        InventoryIssue(
          kind: InventoryIssueKind.drift,
          code: 'incompatible-root-evidence',
          path: subjectPath,
          message: '${rootKind.wireName}: $message',
        ),
      );
    }

    final allowed = allowedKinds[rootKind] ?? const <String>{};
    if (evidence.isEmpty) {
      incompatible('root tag has no structural evidence.');
      return false;
    }
    final wrongKinds = evidence
        .where((entry) => !allowed.contains(entry.kind))
        .map((entry) => entry.kind)
        .toSet();
    if (wrongKinds.isNotEmpty) {
      incompatible(
        'evidence kind(s) ${wrongKinds.toList()..sort()} cannot prove this root kind.',
      );
      return false;
    }

    bool sourceBinds(EvidenceSpec entry) => entry['source'] == subjectPath;
    switch (rootKind) {
      case RuntimeRootKind.manualEntrypoint:
        if (evidence.any(
          (entry) =>
              entry.kind == 'manual-policy' &&
              (entry['target'] ?? subjectPath) == subjectPath,
        )) {
          return true;
        }
        break;
      case RuntimeRootKind.appEntrypoint:
        if (evidence.any(
          (entry) =>
              (entry.kind == 'dart-main' && sourceBinds(entry)) ||
              (entry.kind == 'computed-origin' &&
                  entry['origin'] == RuntimeRootOrigin.main.wireName),
        )) {
          return true;
        }
        break;
      case RuntimeRootKind.vmCallback:
        final annotations = evidence
            .where(
              (entry) =>
                  entry.kind == 'dart-annotation' &&
                  sourceBinds(entry) &&
                  entry['annotation'] == 'pragma' &&
                  entry['value'] == 'vm:entry-point',
            )
            .toList();
        if (annotations.any(
          (annotation) => evidence.any(
            (entry) =>
                (entry.kind == 'dart-call-argument' ||
                    entry.kind == 'source-call-token') &&
                entry['argument'] == annotation['symbol'],
          ),
        )) {
          return true;
        }
        break;
      case RuntimeRootKind.conventionCallback:
        if (evidence.any(
          (entry) => entry.kind == 'dart-symbol' && sourceBinds(entry),
        )) {
          return true;
        }
        break;
      case RuntimeRootKind.tooling:
        if (_hasToolInvocationEvidence(subjectPath, evidence) ||
            evidence.any(
              (entry) =>
                  entry.kind == 'computed-origin' &&
                  entry['origin'] == RuntimeRootOrigin.tooling.wireName,
            )) {
          return true;
        }
        break;
      case RuntimeRootKind.nativeRegistration:
      case RuntimeRootKind.generated:
      case RuntimeRootKind.headlessPlugin:
      case RuntimeRootKind.compatibility:
      case RuntimeRootKind.resource:
        if (evidence.any(sourceBinds)) return true;
        break;
    }
    incompatible(
      'validated evidence is not structurally bound to the declared subject.',
    );
    return false;
  }

  static void _validateDeclarationAgainstComputed(
    DeclarationSpec declaration,
    DartFileInventory file,
    bool evidenceValid,
    List<InventoryIssue> issues,
  ) {
    void drift(String code, String message) {
      issues.add(
        InventoryIssue(
          kind: InventoryIssueKind.drift,
          code: code,
          path: declaration.path,
          message: message,
        ),
      );
    }

    if (declaration.rootKinds.contains(RuntimeRootKind.manualEntrypoint) &&
        !file.origins.contains(RuntimeRootOrigin.manual)) {
      drift(
        'manual-kind-without-origin',
        'manual-entrypoint tag cannot create a manual origin.',
      );
    }
    if (declaration.rootKinds.contains(RuntimeRootKind.tooling) &&
        !file.origins.contains(RuntimeRootOrigin.tooling)) {
      drift(
        'tooling-kind-without-origin',
        'tooling tag cannot create an origin.',
      );
    }
    if (declaration.disposition == ReviewDisposition.explainedRoot &&
        file.origins.isEmpty &&
        (!evidenceValid || declaration.rootKinds.isEmpty)) {
      drift(
        'explained-root-without-proof',
        'explained-root needs a computed origin or validated restricted evidence.',
      );
    }
    if (declaration.disposition == ReviewDisposition.candidate &&
        file.bucket != ReachabilityBucket.unrooted) {
      drift(
        'stale-candidate',
        'A candidate became reachable and needs human re-review.',
      );
    }
  }

  static bool _isConventionEntrypoint(String path) =>
      path == 'test/flutter_test_config.dart' ||
      (path.startsWith('test/') && path.endsWith('_test.dart')) ||
      (path.startsWith('integration_test/') && path.endsWith('_test.dart'));

  static Set<String> _closure(
    Set<String> roots,
    Map<String, Set<String>> edges,
  ) {
    final reached = <String>{};
    final pending = roots.where(edges.containsKey).toList();
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!reached.add(current)) continue;
      pending.addAll(
        edges[current]!.where((target) => !reached.contains(target)),
      );
    }
    return reached;
  }

  static ReachabilityBucket _bucketFor(Set<RuntimeRootOrigin> origins) {
    if (origins.contains(RuntimeRootOrigin.main)) {
      return ReachabilityBucket.mainReachable;
    }
    if (origins.contains(RuntimeRootOrigin.manual)) {
      return ReachabilityBucket.manualRootReachable;
    }
    if (origins.contains(RuntimeRootOrigin.tooling)) {
      return ReachabilityBucket.toolingReachable;
    }
    if (origins.contains(RuntimeRootOrigin.testIntegration)) {
      return ReachabilityBucket.testIntegrationReachable;
    }
    return ReachabilityBucket.unrooted;
  }
}

class _ParsedDartUnit {
  _ParsedDartUnit({
    required this.path,
    required this.source,
    required this.directiveUris,
    required this.hasMain,
    required this.mainOffset,
    required this.topLevelSymbols,
    required this.annotations,
    required this.calls,
    required this.commandArguments,
    required this.vmEntrypoints,
  });

  factory _ParsedDartUnit.fromParseResult(
    String path,
    ParseStringResult result,
  ) {
    final directives = <String>[];
    for (final directive in result.unit.directives) {
      if (directive is UriBasedDirective) {
        final value = directive.uri.stringValue;
        if (value == null) {
          throw FormatException(
            'Directive at ${directive.offset} has a non-static URI.',
          );
        }
        directives.add(value);
      }
      if (directive is ImportDirective || directive is ExportDirective) {
        final configurations = switch (directive) {
          ImportDirective() => directive.configurations,
          ExportDirective() => directive.configurations,
          _ => const <Configuration>[],
        };
        for (final configuration in configurations) {
          final value = configuration.uri.stringValue;
          if (value == null) {
            throw FormatException(
              'Conditional directive at ${configuration.offset} has a non-static URI.',
            );
          }
          directives.add(value);
        }
      }
    }
    final mains = result.unit.declarations
        .whereType<FunctionDeclaration>()
        .where((declaration) => declaration.name.lexeme == 'main')
        .toList();
    final visitor = _StructuralDartVisitor();
    result.unit.accept(visitor);
    return _ParsedDartUnit(
      path: path,
      source: result.content,
      directiveUris: List.unmodifiable(directives),
      hasMain: mains.isNotEmpty,
      mainOffset: mains.isEmpty ? null : mains.first.offset,
      topLevelSymbols: Set.unmodifiable(
        result.unit.declarations
            .whereType<NamedCompilationUnitMember>()
            .map((entry) => entry.name.lexeme)
            .toSet(),
      ),
      annotations: List.unmodifiable(visitor.annotations),
      calls: List.unmodifiable(visitor.calls),
      commandArguments: List.unmodifiable(visitor.commandArguments),
      vmEntrypoints: Set.unmodifiable(visitor.vmEntrypoints),
    );
  }

  final String path;
  final String source;
  final List<String> directiveUris;
  final bool hasMain;
  final int? mainOffset;
  final Set<String> topLevelSymbols;
  final List<_AnnotationRelation> annotations;
  final List<_CallRelation> calls;
  final List<_CommandArgumentRelation> commandArguments;
  final Set<String> vmEntrypoints;
}

class _AnnotationRelation {
  const _AnnotationRelation({
    required this.symbol,
    required this.name,
    required this.value,
  });

  final String symbol;
  final String name;
  final String value;
}

class _CallRelation {
  const _CallRelation({required this.callee, required this.arguments});

  final String callee;
  final List<String> arguments;
}

class _CommandArgumentRelation {
  const _CommandArgumentRelation({required this.option, required this.target});

  final String option;
  final String target;
}

class _MaskedLexicalSource {
  const _MaskedLexicalSource({required this.structure, required this.values});

  final String structure;
  final String values;
}

class _StructuralDartVisitor extends RecursiveAstVisitor<void> {
  final List<_AnnotationRelation> annotations = <_AnnotationRelation>[];
  final List<_CallRelation> calls = <_CallRelation>[];
  final List<_CommandArgumentRelation> commandArguments =
      <_CommandArgumentRelation>[];
  final Set<String> vmEntrypoints = <String>{};
  final Map<String, String> _stringConstants = <String, String>{};

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final initializer = node.initializer;
    if (initializer is StringLiteral && initializer.stringValue != null) {
      _stringConstants[node.name.lexeme] = initializer.stringValue!;
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _recordAnnotations(node.name.lexeme, node.metadata);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _recordAnnotations(node.name.lexeme, node.metadata);
    super.visitClassDeclaration(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target?.toSource();
    final callee = target == null
        ? node.methodName.name
        : '$target.${node.methodName.name}';
    calls.add(
      _CallRelation(
        callee: callee,
        arguments: node.argumentList.arguments
            .map(_argumentValue)
            .toList(growable: false),
      ),
    );
    if (const <String>{
      'Process.run',
      'Process.runSync',
      'Process.start',
    }.contains(callee)) {
      for (final argument in node.argumentList.arguments) {
        final expression = argument is NamedExpression
            ? argument.expression
            : argument;
        if (expression is! ListLiteral) continue;
        final values = expression.elements
            .whereType<Expression>()
            .map(_resolvedCommandValue)
            .toList(growable: false);
        for (var index = 0; index + 1 < values.length; index++) {
          final option = values[index];
          final target = values[index + 1];
          if (option != null && target != null && option.startsWith('-')) {
            commandArguments.add(
              _CommandArgumentRelation(option: option, target: target),
            );
          }
        }
      }
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    calls.add(
      _CallRelation(
        callee: node.function.toSource(),
        arguments: node.argumentList.arguments
            .map(_argumentValue)
            .toList(growable: false),
      ),
    );
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    calls.add(
      _CallRelation(
        callee: node.constructorName.toSource(),
        arguments: node.argumentList.arguments
            .map(_argumentValue)
            .toList(growable: false),
      ),
    );
    super.visitInstanceCreationExpression(node);
  }

  void _recordAnnotations(String symbol, NodeList<Annotation> metadata) {
    for (final annotation in metadata) {
      final name = annotation.name.name;
      final arguments = annotation.arguments?.arguments ?? const <Expression>[];
      final value = arguments.isEmpty ? '' : _argumentValue(arguments.first);
      annotations.add(
        _AnnotationRelation(symbol: symbol, name: name, value: value),
      );
      if (name == 'pragma' && value == 'vm:entry-point') {
        vmEntrypoints.add(symbol);
      }
    }
  }

  static String _argumentValue(Expression expression) {
    if (expression is StringLiteral) return expression.stringValue ?? '';
    if (expression is SimpleIdentifier) return expression.name;
    if (expression is PrefixedIdentifier) return expression.toSource();
    if (expression is NamedExpression) {
      return '${expression.name.label.name}:${_argumentValue(expression.expression)}';
    }
    return expression.toSource();
  }

  String? _resolvedCommandValue(Expression expression) {
    if (expression is StringLiteral) return expression.stringValue;
    if (expression is SimpleIdentifier) {
      return _stringConstants[expression.name];
    }
    return null;
  }
}

Map<String, Object?> _object(Object? value, String label) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry('$key', value));
  }
  throw FormatException('$label must be a JSON object.');
}

List<Object?> _list(Object? value, String label) {
  if (value is List<Object?>) return value;
  if (value is List) return value.cast<Object?>();
  throw FormatException('$label must be a JSON array.');
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value;
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('$key must be a boolean.');
  return value;
}

List<String> _stringList(Object? value, String label) {
  final values = _list(value, label);
  if (values.any((entry) => entry is! String)) {
    throw FormatException('$label must contain only strings.');
  }
  return values.cast<String>();
}
