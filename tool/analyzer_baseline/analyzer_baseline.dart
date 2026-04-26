import 'dart:collection';
import 'dart:io';

const baselinePath = 'tool/analyzer_baseline/flutter_analyze_baseline.tsv';

final _findingLinePattern = RegExp(
  r'^\s*(info|warning|error)\s+•\s+(.+)\s+•\s+(.+):(\d+):(\d+)\s+•\s+([A-Za-z0-9_]+)\s*$',
);

final _findingPrefixPattern = RegExp(r'^\s*(info|warning|error)\s+•');

class AnalyzerFinding {
  const AnalyzerFinding({
    required this.severity,
    required this.message,
    required this.path,
    required this.line,
    required this.column,
    required this.rule,
  });

  final String severity;
  final String message;
  final String path;
  final int line;
  final int column;
  final String rule;

  AnalyzerFindingKey get key => AnalyzerFindingKey(
    severity: severity,
    rule: rule,
    path: path,
    message: message,
  );
}

class AnalyzerFindingKey implements Comparable<AnalyzerFindingKey> {
  const AnalyzerFindingKey({
    required this.severity,
    required this.rule,
    required this.path,
    required this.message,
  });

  final String severity;
  final String rule;
  final String path;
  final String message;

  @override
  int compareTo(AnalyzerFindingKey other) {
    final severityCompare = severity.compareTo(other.severity);
    if (severityCompare != 0) return severityCompare;

    final ruleCompare = rule.compareTo(other.rule);
    if (ruleCompare != 0) return ruleCompare;

    final pathCompare = path.compareTo(other.path);
    if (pathCompare != 0) return pathCompare;

    return message.compareTo(other.message);
  }

  @override
  bool operator ==(Object other) {
    return other is AnalyzerFindingKey &&
        other.severity == severity &&
        other.rule == rule &&
        other.path == path &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hash(severity, rule, path, message);

  @override
  String toString() => '$severity • $message • $path • $rule';
}

class ParsedAnalyzerOutput {
  const ParsedAnalyzerOutput({
    required this.findings,
    required this.malformedFindingLines,
  });

  final List<AnalyzerFinding> findings;
  final List<String> malformedFindingLines;

  Iterable<AnalyzerFinding> get errors =>
      findings.where((finding) => finding.severity == 'error');

  int countWhereSeverity(String severity) =>
      findings.where((finding) => finding.severity == severity).length;
}

class AnalyzerBaselineSnapshot {
  const AnalyzerBaselineSnapshot(this.counts);

  final Map<AnalyzerFindingKey, int> counts;

  int get total => counts.values.fold<int>(0, (sum, count) => sum + count);
}

class AnalyzerDelta {
  const AnalyzerDelta({
    required this.key,
    required this.baselineCount,
    required this.currentCount,
  });

  final AnalyzerFindingKey key;
  final int baselineCount;
  final int currentCount;

  int get delta => currentCount - baselineCount;
  int get removed => baselineCount - currentCount;
}

class AnalyzerBaselineComparison {
  const AnalyzerBaselineComparison({
    required this.currentSnapshot,
    required this.baselineSnapshot,
    required this.errors,
    required this.newDebt,
    required this.removedDebt,
    required this.malformedFindingLines,
  });

  final AnalyzerBaselineSnapshot currentSnapshot;
  final AnalyzerBaselineSnapshot baselineSnapshot;
  final List<AnalyzerFinding> errors;
  final List<AnalyzerDelta> newDebt;
  final List<AnalyzerDelta> removedDebt;
  final List<String> malformedFindingLines;

  bool get hasBlockingIssues =>
      errors.isNotEmpty ||
      newDebt.isNotEmpty ||
      malformedFindingLines.isNotEmpty;
}

AnalyzerFinding? parseAnalyzerFindingLine(String line) {
  final match = _findingLinePattern.firstMatch(line);
  if (match == null) return null;

  return AnalyzerFinding(
    severity: match.group(1)!,
    message: match.group(2)!.trim(),
    path: match.group(3)!.trim(),
    line: int.parse(match.group(4)!),
    column: int.parse(match.group(5)!),
    rule: match.group(6)!.trim(),
  );
}

ParsedAnalyzerOutput parseAnalyzerOutput(String output) {
  final findings = <AnalyzerFinding>[];
  final malformedFindingLines = <String>[];

  for (final line in output.split(RegExp(r'\r?\n'))) {
    final finding = parseAnalyzerFindingLine(line);
    if (finding != null) {
      findings.add(finding);
      continue;
    }

    if (_findingPrefixPattern.hasMatch(line)) {
      malformedFindingLines.add(line);
    }
  }

  return ParsedAnalyzerOutput(
    findings: findings,
    malformedFindingLines: malformedFindingLines,
  );
}

AnalyzerBaselineSnapshot snapshotWarningInfoFindings(
  Iterable<AnalyzerFinding> findings,
) {
  final counts = <AnalyzerFindingKey, int>{};
  for (final finding in findings) {
    if (finding.severity == 'error') continue;
    counts.update(finding.key, (count) => count + 1, ifAbsent: () => 1);
  }
  return AnalyzerBaselineSnapshot(counts);
}

String buildBaselineTsv(
  ParsedAnalyzerOutput parsed, {
  required DateTime generatedAt,
  required String command,
}) {
  final errors = parsed.errors.toList();
  if (errors.isNotEmpty) {
    throw StateError('Cannot generate analyzer baseline with errors present.');
  }
  if (parsed.malformedFindingLines.isNotEmpty) {
    throw StateError(
      'Cannot generate analyzer baseline with malformed finding lines.',
    );
  }

  final snapshot = snapshotWarningInfoFindings(parsed.findings);
  final keys = snapshot.counts.keys.toList()..sort();
  final buffer = StringBuffer()
    ..writeln('# Flutter analyzer warning/info baseline')
    ..writeln('# Generated: ${generatedAt.toUtc().toIso8601String()}')
    ..writeln('# Command: $command')
    ..writeln('# Total warning/info findings: ${snapshot.total}')
    ..writeln('# Columns: count\tseverity\trule\tpath\tmessage');

  for (final key in keys) {
    buffer
      ..write(snapshot.counts[key])
      ..write('\t')
      ..write(_escapeTsv(key.severity))
      ..write('\t')
      ..write(_escapeTsv(key.rule))
      ..write('\t')
      ..write(_escapeTsv(key.path))
      ..write('\t')
      ..writeln(_escapeTsv(key.message));
  }

  return buffer.toString();
}

AnalyzerBaselineSnapshot readBaselineTsv(String content) {
  final counts = <AnalyzerFindingKey, int>{};
  var lineNumber = 0;

  for (final line in content.split(RegExp(r'\r?\n'))) {
    lineNumber += 1;
    if (line.trim().isEmpty || line.startsWith('#')) continue;

    final fields = line.split('\t');
    if (fields.length != 5) {
      throw FormatException('Invalid baseline row at line $lineNumber.');
    }

    final count = int.tryParse(fields[0]);
    if (count == null || count < 0) {
      throw FormatException('Invalid baseline count at line $lineNumber.');
    }

    final severity = _unescapeTsv(fields[1]);
    if (severity == 'error') {
      throw FormatException('Analyzer errors cannot be baselined.');
    }
    if (severity != 'warning' && severity != 'info') {
      throw FormatException('Invalid baseline severity at line $lineNumber.');
    }

    final key = AnalyzerFindingKey(
      severity: severity,
      rule: _unescapeTsv(fields[2]),
      path: _unescapeTsv(fields[3]),
      message: _unescapeTsv(fields[4]),
    );
    counts[key] = (counts[key] ?? 0) + count;
  }

  return AnalyzerBaselineSnapshot(counts);
}

AnalyzerBaselineComparison compareAnalyzerBaseline({
  required ParsedAnalyzerOutput current,
  required AnalyzerBaselineSnapshot baseline,
}) {
  final currentSnapshot = snapshotWarningInfoFindings(current.findings);
  final newDebt = <AnalyzerDelta>[];
  final removedDebt = <AnalyzerDelta>[];
  final allKeys = SplayTreeSet<AnalyzerFindingKey>()
    ..addAll(currentSnapshot.counts.keys)
    ..addAll(baseline.counts.keys);

  for (final key in allKeys) {
    final currentCount = currentSnapshot.counts[key] ?? 0;
    final baselineCount = baseline.counts[key] ?? 0;
    if (currentCount > baselineCount) {
      newDebt.add(
        AnalyzerDelta(
          key: key,
          baselineCount: baselineCount,
          currentCount: currentCount,
        ),
      );
    } else if (baselineCount > currentCount) {
      removedDebt.add(
        AnalyzerDelta(
          key: key,
          baselineCount: baselineCount,
          currentCount: currentCount,
        ),
      );
    }
  }

  return AnalyzerBaselineComparison(
    currentSnapshot: currentSnapshot,
    baselineSnapshot: baseline,
    errors: current.errors.toList(),
    newDebt: newDebt,
    removedDebt: removedDebt,
    malformedFindingLines: current.malformedFindingLines,
  );
}

int runAnalyzerBaselineCli(List<String> args) {
  if (args.isEmpty || args.first == '--help' || args.first == '-h') {
    _writeUsage(stdout);
    return args.isEmpty ? 2 : 0;
  }

  switch (args.first) {
    case 'generate':
      return _runGenerate(args.skip(1).toList());
    case 'compare':
      return _runCompare(args.skip(1).toList());
    default:
      stderr.writeln('Unknown command: ${args.first}');
      _writeUsage(stderr);
      return 2;
  }
}

int _runGenerate(List<String> args) {
  final options = _parseOptions(args);
  final inputPath = options['input'];
  final outputPath = options['output'] ?? baselinePath;
  final command =
      options['command'] ??
      'flutter analyze --no-fatal-infos --no-fatal-warnings';

  if (inputPath == null) {
    stderr.writeln('Missing required --input for generate.');
    return 2;
  }

  final parsed = parseAnalyzerOutput(File(inputPath).readAsStringSync());
  final baseline = buildBaselineTsv(
    parsed,
    generatedAt: DateTime.now(),
    command: command,
  );
  final outputFile = File(outputPath);
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(baseline);
  stdout.writeln(
    'Wrote analyzer baseline: $outputPath '
    '(${snapshotWarningInfoFindings(parsed.findings).total} findings)',
  );
  return 0;
}

int _runCompare(List<String> args) {
  final options = _parseOptions(args);
  final inputPath = options['input'];
  final baselineFilePath = options['baseline'] ?? baselinePath;

  if (inputPath == null) {
    stderr.writeln('Missing required --input for compare.');
    return 2;
  }

  final current = parseAnalyzerOutput(File(inputPath).readAsStringSync());
  final baseline = readBaselineTsv(File(baselineFilePath).readAsStringSync());
  final comparison = compareAnalyzerBaseline(
    current: current,
    baseline: baseline,
  );

  _writeComparison(comparison);
  return comparison.hasBlockingIssues ? 1 : 0;
}

Map<String, String> _parseOptions(List<String> args) {
  final options = <String, String>{};
  var index = 0;
  while (index < args.length) {
    final arg = args[index];
    if (!arg.startsWith('--')) {
      throw FormatException('Unexpected argument: $arg');
    }
    if (index + 1 >= args.length) {
      throw FormatException('Missing value for $arg');
    }
    options[arg.substring(2)] = args[index + 1];
    index += 2;
  }
  return options;
}

void _writeComparison(AnalyzerBaselineComparison comparison) {
  stdout
    ..writeln('Analyzer baseline comparison')
    ..writeln(
      'Current warning/info findings: ${comparison.currentSnapshot.total}',
    )
    ..writeln(
      'Baseline warning/info findings: ${comparison.baselineSnapshot.total}',
    )
    ..writeln('Analyzer errors: ${comparison.errors.length}')
    ..writeln('New analyzer debt: ${_sumNewDebt(comparison.newDebt)}')
    ..writeln(
      'Removed analyzer debt: ${_sumRemovedDebt(comparison.removedDebt)}',
    );

  if (comparison.malformedFindingLines.isNotEmpty) {
    stderr.writeln('Malformed analyzer finding lines:');
    for (final line in comparison.malformedFindingLines.take(20)) {
      stderr.writeln('  $line');
    }
  }

  if (comparison.errors.isNotEmpty) {
    stderr.writeln('Analyzer errors:');
    for (final error in comparison.errors.take(20)) {
      stderr.writeln(
        '  ${error.path}:${error.line}:${error.column} '
        '${error.rule}: ${error.message}',
      );
    }
  }

  if (comparison.newDebt.isNotEmpty) {
    stderr.writeln('New analyzer warning/info debt:');
    for (final debt in comparison.newDebt.take(20)) {
      stderr.writeln(
        '  +${debt.delta} ${debt.key.path} '
        '${debt.key.rule}: ${debt.key.message}',
      );
    }
  }

  if (comparison.removedDebt.isNotEmpty) {
    stdout.writeln('Removed baseline debt opportunities:');
    for (final debt in comparison.removedDebt.take(20)) {
      stdout.writeln(
        '  -${debt.removed} ${debt.key.path} '
        '${debt.key.rule}: ${debt.key.message}',
      );
    }
  }
}

int _sumNewDebt(List<AnalyzerDelta> deltas) =>
    deltas.fold<int>(0, (sum, delta) => sum + delta.delta);

int _sumRemovedDebt(List<AnalyzerDelta> deltas) =>
    deltas.fold<int>(0, (sum, delta) => sum + delta.removed);

String _escapeTsv(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll('\t', r'\t')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');
}

String _unescapeTsv(String value) {
  final buffer = StringBuffer();
  for (var index = 0; index < value.length; index += 1) {
    final char = value[index];
    if (char != r'\') {
      buffer.write(char);
      continue;
    }
    if (index + 1 >= value.length) {
      buffer.write(char);
      continue;
    }
    final next = value[index + 1];
    switch (next) {
      case r'\':
        buffer.write(r'\');
      case 't':
        buffer.write('\t');
      case 'n':
        buffer.write('\n');
      case 'r':
        buffer.write('\r');
      default:
        buffer
          ..write(char)
          ..write(next);
    }
    index += 1;
  }
  return buffer.toString();
}

void _writeUsage(IOSink sink) {
  sink.writeln('Usage:');
  sink.writeln(
    '  dart run tool/analyzer_baseline/analyzer_baseline.dart '
    'generate --input <flutter-analyze-log> [--output <baseline.tsv>]',
  );
  sink.writeln(
    '  dart run tool/analyzer_baseline/analyzer_baseline.dart '
    'compare --input <flutter-analyze-log> [--baseline <baseline.tsv>]',
  );
}

void main(List<String> args) {
  try {
    exitCode = runAnalyzerBaselineCli(args);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 2;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    exitCode = 2;
  } on StateError catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  }
}
