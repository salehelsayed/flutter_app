import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'runtime_root_inventory.dart';

/// Refreshes derived evidence without changing previously reviewed decisions.
///
/// New integration_test/ and scripts/ mains use the inventory's conservative
/// QA policy: visible, but not tooling roots or proof of release invocation.
/// New callbacks, other entrypoints, and changed evidence values need review.
RuntimeRootsRegeneration regenerateRuntimeRoots({
  required String repoRoot,
  required String manifestPath,
  bool write = false,
  GitPathLister? gitPathLister,
}) {
  final file = File(manifestPath);
  final original = file.readAsStringSync();
  final manifest = jsonDecode(original) as Map<String, dynamic>;
  final changes = <Map<String, Object?>>[];

  RuntimeRootInventoryResult scan() {
    final result = RuntimeRootInventory(
      repoRoot: repoRoot,
      manifest: RuntimeRootsManifest.fromJsonString(jsonEncode(manifest)),
      gitPathLister: gitPathLister,
    ).scan();
    if (!result.trustworthy) {
      throw FormatException(
        'Refusing to regenerate an untrustworthy inventory: '
        '${result.issues.where((issue) => issue.kind == InventoryIssueKind.fatal).map((issue) => '${issue.code}: ${issue.path}').join(', ')}',
      );
    }
    return result;
  }

  scan();
  const commandSource = 'tool/sims/critical_features.json';
  final commandFile = File(p.join(repoRoot, commandSource));
  if (commandFile.existsSync()) {
    final source = jsonDecode(commandFile.readAsStringSync());
    final capabilities = source is Map ? source['capabilities'] : null;
    if (capabilities is! List) {
      throw const FormatException('SIMS capabilities must be a JSON array.');
    }
    final locations = <String, List<String>>{};
    for (var index = 0; index < capabilities.length; index++) {
      final capability = capabilities[index];
      final command = capability is Map ? capability['command'] : null;
      if (command is! List) continue;
      for (var argument = 0; argument < command.length; argument++) {
        final value = command[argument];
        if (value is String) {
          locations
              .putIfAbsent(value, () => <String>[])
              .add('capabilities.$index.command.$argument');
        }
      }
    }
    for (final section in <String>[
      'externalEntrypoints',
      'declarations',
      'restrictedRoots',
    ]) {
      for (final row in manifest[section] as List) {
        for (final evidence in row['evidence'] as List) {
          if (evidence['kind'] != 'json-value' ||
              evidence['source'] != commandSource ||
              !RegExp(
                r'^capabilities\.\d+\.command\.\d+$',
              ).hasMatch(evidence['keyPath'] as String? ?? '')) {
            continue;
          }
          final matches = locations[evidence['value']];
          if (matches == null || matches.contains(evidence['keyPath'])) {
            continue;
          }
          changes.add(<String, Object?>{
            'kind': 'evidence-key',
            'path': row['path'],
            'source': commandSource,
            'from': evidence['keyPath'],
            'to': matches.first,
            'matchingLocations': matches.length,
          });
          evidence['keyPath'] = matches.first;
        }
      }
    }
  }

  // Restore existing invocation evidence before classifying new entrypoints.
  final repaired = scan();
  final reviewedPaths = (manifest['externalEntrypoints'] as List)
      .map((row) => row['path'])
      .toSet();
  for (final entry in repaired.externalEntrypoints) {
    if (reviewedPaths.contains(entry.path) ||
        !(entry.path.startsWith('integration_test/') ||
            entry.path.startsWith('scripts/'))) {
      continue;
    }
    (manifest['externalEntrypoints'] as List).add(<String, Object?>{
      'path': entry.path,
      'owner': 'QA / release',
      'reason':
          'Non-convention Dart main remains visible pending exact invocation ownership.',
      'condition':
          'Remove or reclassify only after its caller and replacement proof are reviewed.',
      'seedsTooling': false,
      'evidence': <Map<String, Object?>>[
        <String, Object?>{'kind': 'dart-main', 'source': entry.path},
      ],
    });
    changes.add(<String, Object?>{'kind': 'qa-entrypoint', 'path': entry.path});
  }
  final inventory = scan();
  if (write && changes.isNotEmpty) {
    // A failed scan never touches the file; publish the complete JSON at once.
    final temporary = File('${file.path}.tmp.$pid');
    try {
      temporary.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
        flush: true,
      );
      temporary.renameSync(file.path);
    } finally {
      if (temporary.existsSync()) temporary.deleteSync();
    }
  }
  return RuntimeRootsRegeneration(
    changes: changes,
    inventory: inventory,
    written: write && changes.isNotEmpty,
  );
}

class RuntimeRootsRegeneration {
  const RuntimeRootsRegeneration({
    required this.changes,
    required this.inventory,
    required this.written,
  });

  final List<Map<String, Object?>> changes;
  final RuntimeRootInventoryResult inventory;
  final bool written;

  int get exitCode => inventory.exitCodeFor(check: true);

  Map<String, Object?> toJson() => <String, Object?>{
    'written': written,
    'derivedEvidenceKeys': changes
        .where((change) => change['kind'] == 'evidence-key')
        .length,
    'derivedQaEntrypoints': changes
        .where((change) => change['kind'] == 'qa-entrypoint')
        .length,
    'changes': changes,
    'needsDecision': inventory.issues.map((issue) => issue.toJson()).toList(),
  };
}

void main(List<String> arguments) {
  var repoRoot = File.fromUri(Platform.script).parent.parent.parent.path;
  String? manifestPath;
  var write = false;
  final seen = <String>{};
  try {
    for (var index = 0; index < arguments.length; index++) {
      final option = arguments[index];
      if (!seen.add(option)) throw FormatException('Duplicate option: $option');
      if (option == '--write') {
        write = true;
      } else if (option == '--repo-root' || option == '--manifest') {
        if (++index >= arguments.length || arguments[index].startsWith('--')) {
          throw FormatException('Missing value for $option');
        }
        if (option == '--repo-root') {
          repoRoot = arguments[index];
        } else {
          manifestPath = arguments[index];
        }
      } else {
        throw FormatException('Unknown option: $option');
      }
    }
    repoRoot = p.normalize(p.absolute(repoRoot));
    manifestPath ??= 'tool/runtime_roots/runtime_roots.json';
    final result = regenerateRuntimeRoots(
      repoRoot: repoRoot,
      manifestPath: p.isAbsolute(manifestPath)
          ? manifestPath
          : p.join(repoRoot, manifestPath),
      write: write,
    );
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result.toJson()));
    exitCode = result.exitCode;
  } on Object catch (error) {
    stderr.writeln(error);
    stderr.writeln(
      'Usage: dart tool/runtime_roots/regenerate_runtime_roots.dart '
      '[--repo-root <path>] [--manifest <path>] [--write]',
    );
    exitCode = 2;
  }
}
